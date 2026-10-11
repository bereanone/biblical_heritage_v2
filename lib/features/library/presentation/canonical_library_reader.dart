import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/database/elibrary_database.dart';
import '../../../core/database/study_bible_database.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/theme/app_theme_mode.dart';
import '../../../core/theme/app_settings_service.dart';
import '../data/canonical_activation.dart';
import '../data/library_catalog_service.dart';
import '../data/library_document_canonicalizer.dart';
import '../data/library_source_type.dart';
import '../data/library_document_models.dart';
import '../data/library_citation_links.dart';
import '../data/library_document_assets.dart';
import '../data/library_document_repository.dart';
import '../data/elibrary_markup_repository.dart';
import '../data/library_reader_state_writer.dart';
import '../data/library_search_navigation_target.dart';
import '../../search/search_highlight_helper.dart';
import 'canonical_local_image.dart';
import 'canonical_reader_image.dart';
import 'canonical_scroll_diagnostics.dart';
import 'elibrary_highlight_color_picker.dart';
import 'library_document_controller.dart';
import 'reader_tilt_autoscroll_controller.dart';
import 'reader_tilt_autoscroll_controls.dart';
import 'reader_tilt_motion_source.dart';
import 'reader_tilt_preferences.dart';
import 'speech_tilt_binding.dart';
import 'mac_reader_autoscroll_controller.dart';
import 'mac_reader_autoscroll_controls.dart';
import 'library_narration_media_controls.dart';
import 'library_speech_controls.dart';
import 'library_speech_scroll_follower.dart';
import 'library_navigation_tree.dart';
import 'library_verse_popup.dart';
import 'library_book_reader_selection_menu.dart';
import 'canonical_selection_tools.dart';
import '../../reader/presentation/tag_quick_apply_helper.dart';
import '../../reader/presentation/tag_screen_launcher.dart';
import '../../reader/presentation/viewer_passage_models.dart';
import '../../reader/presentation/viewer_range_selection.dart';

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

bool canonicalReaderSupportsLink(String sourceHref, String href) =>
    href.startsWith('studybible-citation:') ||
    resolveLibrarySourceLinkPath(sourceHref, href) != null;

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

// Search emphasis creates child spans; attach the link to every text leaf so
// taps keep working across search and annotation formatting boundaries.
TextSpan _linkedCanonicalSpan(
  TextSpan span,
  GestureRecognizer recognizer,
) => TextSpan(
  text: span.text,
  style: span.style,
  recognizer: recognizer,
  mouseCursor: SystemMouseCursors.click,
  semanticsLabel: span.semanticsLabel,
  locale: span.locale,
  spellOut: span.spellOut,
  children: span.children
      ?.map(
        (child) =>
            child is TextSpan ? _linkedCanonicalSpan(child, recognizer) : child,
      )
      .toList(),
);

List<InlineSpan> canonicalInlineTextSpans({
  required LibraryDocumentBlock block,
  required LibraryFormattedContent formatted,
  required TextStyle bodyStyle,
  required TextStyle referenceStyle,
  required bool showReferenceCode,
  List<String> highlightTerms = const <String>[],
  List<ElibraryMarkupRecord> markups = const [],
  GestureRecognizer? Function(String href)? linkRecognizer,
  bool Function(String book, String locator)? citationResolves,
}) {
  final spans = <InlineSpan>[];
  var offset = 0;
  final validMarkups = markups
      .where(
        (m) =>
            m.deletedAt == null &&
            m.startBlockIndex == 0 &&
            m.endBlockIndex == 0 &&
            m.startCharOffset >= 0 &&
            m.endCharOffset <= block.plainText.length &&
            m.endCharOffset > m.startCharOffset &&
            block.plainText.substring(m.startCharOffset, m.endCharOffset) ==
                m.selectedTextSnapshot,
      )
      .toList();
  // Older accepted generations can gain new citation support without a
  // content migration. Existing authored links and all text stay intact.
  for (final node in linkLibraryCitations(
    restoreLibraryInlineBoundaryWhitespace(
      plainText: block.plainText,
      nodes: formatted.nodes,
    ),
    resolves: citationResolves,
  )) {
    final text = node['type'] == 'line_break'
        ? '\n'
        : node['text']?.toString() ?? '';
    final marks = (node['marks'] as List<Object?>? ?? const <Object?>[])
        .map((value) => value.toString())
        .toSet();
    final href = node['link']?.toString();
    final recognizer = href == null ? null : linkRecognizer?.call(href);
    final inlineScale = node['relative_font_scale'];
    final nodeStyle = bodyStyle.copyWith(
      fontSize:
          inlineScale is num &&
              inlineScale.isFinite &&
              bodyStyle.fontSize != null
          ? bodyStyle.fontSize! * inlineScale.clamp(0.7, 2.0)
          : null,
      fontWeight: marks.contains('bold') ? FontWeight.w700 : null,
      fontStyle: marks.contains('italic') ? FontStyle.italic : null,
      decoration: marks.contains('underline') || recognizer != null
          ? TextDecoration.underline
          : null,
      fontFeatures: marks.contains('superscript')
          ? const <FontFeature>[FontFeature.superscripts()]
          : marks.contains('subscript')
          ? const <FontFeature>[FontFeature.subscripts()]
          : null,
    );
    final boundaries = <int>{0, text.length};
    for (final markup in validMarkups) {
      boundaries.add((markup.startCharOffset - offset).clamp(0, text.length));
      boundaries.add((markup.endCharOffset - offset).clamp(0, text.length));
    }
    final sorted = boundaries.toList()..sort();
    for (var i = 1; i < sorted.length; i++) {
      final first = sorted[i - 1], last = sorted[i];
      if (first == last) continue;
      var style = nodeStyle;
      for (final markup in validMarkups) {
        if (markup.startCharOffset >= offset + last ||
            markup.endCharOffset <= offset + first) {
          continue;
        }
        if (markup.markupType == ElibraryMarkupRepository.underlineType) {
          style = style.copyWith(
            decoration: TextDecoration.combine([
              if (style.decoration != null) style.decoration!,
              TextDecoration.underline,
            ]),
          );
        } else if (markup.isHighlight) {
          final hex = markup.color.replaceFirst('#', '');
          final value = int.tryParse(
            hex.length == 6 ? 'FF$hex' : hex,
            radix: 16,
          );
          if (value != null) {
            style = style.copyWith(backgroundColor: Color(value));
          }
        }
      }
      final slice = text.substring(first, last);
      final part = highlightTerms.isEmpty
          ? TextSpan(text: slice, style: style)
          : TextSpan(
              children: buildHighlightedSearchSpans(
                slice,
                highlightTerms,
                baseStyle: style,
              ),
            );
      spans.add(
        recognizer == null ? part : _linkedCanonicalSpan(part, recognizer),
      );
    }
    offset += text.length;
  }
  final code = canonicalInlineReferenceCode(block, visible: showReferenceCode);
  if (code != null) spans.add(TextSpan(text: ' $code', style: referenceStyle));
  return spans;
}

/// The heading the reader is currently inside of: the last heading in
/// document order at or before [currentOrder]. Returns `null` if
/// [currentOrder] falls before every heading (e.g. still in front matter).
@visibleForTesting
LibraryDocumentBlock? canonicalContentsCurrentHeading({
  required List<LibraryDocumentBlock> headings,
  required int currentOrder,
}) {
  LibraryDocumentBlock? currentHeading;
  for (final heading in headings) {
    if (heading.displayOrder > currentOrder) break;
    currentHeading = heading;
  }
  return currentHeading;
}

@visibleForTesting
Map<String, int> canonicalContentsHeadingDepths({
  required List<LibraryDocumentBlock> headings,
  required List<LibraryCatalogNavigationItem> navigationItems,
}) {
  int localDepth(LibraryDocumentBlock heading) => switch (heading.headingRole) {
    'section' => 1,
    'minor' => 2,
    _ => 0,
  };

  if (navigationItems.isEmpty) {
    return <String, int>{
      for (final heading in headings) heading.id: localDepth(heading),
    };
  }

  bool isSupportEntry(LibraryCatalogNavigationItem item) =>
      switch (item.contentKind?.trim().toLowerCase()) {
        'cover' ||
        'title_page' ||
        'about' ||
        'copyright' ||
        'foreword' ||
        'introduction' => true,
        _ => false,
      };

  final tree = buildLibraryNavigationTree(navigationItems);
  final navigationDepths = <String, int>{};
  void visit(List<LibraryCatalogNavigationItem> items, int depth) {
    for (final item in items) {
      final supportEntry = isSupportEntry(item);
      if (!supportEntry) navigationDepths[item.id] = depth;
      visit(
        tree.childrenByParent[item.id] ?? const [],
        supportEntry ? depth : depth + 1,
      );
    }
  }

  visit(tree.childrenByParent[null] ?? const [], 0);

  final usableItems = tree.items
      .where((item) => navigationDepths.containsKey(item.id))
      .toList(growable: false);
  final itemsByHref = <String, List<LibraryCatalogNavigationItem>>{};
  final itemsByLabel = <String, List<LibraryCatalogNavigationItem>>{};
  for (final item in usableItems) {
    final href = item.href?.trim() ?? '';
    if (href.isNotEmpty) {
      itemsByHref
          .putIfAbsent(normalizeLibrarySourceHref(href), () => [])
          .add(item);
    }
    final label = _normalizeCanonicalContentsLabel(item.label);
    if (label.isNotEmpty) itemsByLabel.putIfAbsent(label, () => []).add(item);
  }

  final result = <String, int>{};
  for (final heading in headings) {
    LibraryCatalogNavigationItem? match;
    final sourceHref = heading.sourceHref?.trim() ?? '';
    if (sourceHref.isNotEmpty) {
      final hrefMatches = itemsByHref[normalizeLibrarySourceHref(sourceHref)];
      if (hrefMatches != null && hrefMatches.isNotEmpty) {
        final headingLabel = _normalizeCanonicalContentsLabel(
          heading.plainText,
        );
        match = hrefMatches.firstWhere(
          (item) =>
              _normalizeCanonicalContentsLabel(item.label) == headingLabel,
          orElse: () => hrefMatches.first,
        );
      }
    }
    if (match == null) {
      final labelMatches =
          itemsByLabel[_normalizeCanonicalContentsLabel(heading.plainText)];
      if (labelMatches != null && labelMatches.isNotEmpty) {
        match = labelMatches.first;
      }
    }
    result[heading.id] =
        (match == null ? 0 : navigationDepths[match.id] ?? 0) +
        localDepth(heading);
  }
  return result;
}

String _normalizeCanonicalContentsLabel(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

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

/// Repairs only the proven legacy ZIP-as-text failure, not accepted prose.
Future<bool> _hasLegacyZipText(
  LibraryDocumentRepository repository,
  String itemId,
  File source,
) async {
  final rows = await repository.db.query(
    'library_document_blocks',
    columns: ['plain_text'],
    where: 'library_item_id = ?',
    whereArgs: [itemId],
    orderBy: 'display_order',
    limit: 3,
  );
  final zipText = rows.any((row) {
    final text = (row['plain_text']?.toString() ?? '').trimLeft();
    return text.startsWith('PK\u0003\u0004') ||
        (text.startsWith('PK') &&
            (text.contains('mimetype') || text.contains('META-INF/')));
  });
  return zipText &&
      await source.exists() &&
      librarySourceIsEpub(await source.readAsBytes(), path: source.path);
}

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
  final db = await ELibraryDatabase.instance.database;
  final repository = LibraryDocumentRepository(db);
  final repairZipText = await _hasLegacyZipText(repository, item.id, source);
  if (await repository.isComplete(item.id) && !repairZipText) {
    return CanonicalReaderPreparation(
      repository: repository,
      sourceRoot: source.parent,
    );
  }
  if (!await source.exists()) return null;
  final outcome = await CanonicalActivation.activate(
    db: db,
    libraryItemId: item.id,
    source: source,
    force: repairZipText,
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
  // The canonical reader is the EPUB reader. Provenance must not choose a
  // second rendering/navigation model. Failed EPUB preparation is reported
  // explicitly, while the source and prior accepted content remain intact.
  return item.relativePath.trim().isNotEmpty;
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
  // Version upgrades are explicit maintenance. A read must not replace
  // accepted content or move saved selections simply because code changed.
  final alreadyComplete = await repository.isComplete(item.id);
  final repairZipText = await _hasLegacyZipText(repository, item.id, source);
  if (!alreadyComplete || repairZipText) {
    if (!await source.exists()) return null;
    final outcome = await CanonicalActivation.activate(
      db: db,
      libraryItemId: item.id,
      source: source,
      force: repairZipText,
      applyStoragePolicy: true,
      rootPath: rootPath,
    );
    if (!outcome.isReady) return null;
  }

  final embeddedRoot = await LibraryDocumentAssets.restore(
    db: db,
    itemId: item.id,
    libraryRoot: Directory(rootPath),
  );
  final assetDirectory = Directory(
    p.join(source.parent.path, '_canonical_assets', item.id),
  );
  return CanonicalReaderPreparation(
    repository: repository,
    sourceRoot:
        embeddedRoot ??
        (await assetDirectory.exists() ? assetDirectory : source.parent),
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
          if (preparation == null) {
            // EPUB Contents and rendering must never fall back to the legacy
            // reader: it builds both from separate models and can silently
            // open a valid-looking but wrong section. Capture/html retains
            // its historical fallback while EPUB reports preparation failure
            // explicitly, preserving correctness over a misleading route.
            if (supportsCanonicalEpubReader(widget.item)) {
              final goBack = widget.onBack ?? () => Navigator.of(context).pop();
              return Scaffold(
                appBar: AppBar(
                  leading: BackButton(onPressed: goBack),
                  title: const Text('Unable to Open Book'),
                ),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'This book could not be prepared for reading. Its '
                          'source file may need to be re-downloaded.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            if (widget.onLibrary != null)
                              OutlinedButton(
                                onPressed: widget.onLibrary,
                                child: const Text('Back to Library'),
                              ),
                            FilledButton(
                              onPressed: goBack,
                              child: const Text('Go Back'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return widget.legacyBuilder(context);
          }
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
  Timer? _positionSaveTimer;
  Future<void> _positionSave = Future<void>.value();
  int _latestVisibleOrder = 0;
  String? _selectedRecordedCursor;
  String? _spokenBlockId;
  double _fontScale = 1;
  bool _showRefCodes = false;
  bool Function(String book, String locator)? _citationResolves;
  int? _initialSearchOrder;
  int? _contentsJumpOrder;
  bool _searchTargetPositioned = false;
  int _explicitTargetMountRevision = 0;
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
      // ScrollablePositionedList lays unloaded rows out at zero height. If a
      // previously measured variable-height row is evicted while the reader
      // remains mounted, the sliver geometry collapses behind the viewport
      // and the page visibly jumps/flashes. Keep blocks once measured for
      // this reader session; disposal still releases the complete cache.
      preserveLoadedGeometry: true,
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
    // iOS never gets continuous pixel autoscroll (shouldUseSteadyReaderAuto-
    // scroll deliberately excludes it, see its test coverage), but it can
    // still host narration-only mode: narrationControlsPacing forces
    // isPixelScrolling false, so this controller only tracks play/pause,
    // speed, and speech-driven block advancement — no scroll-motion UI.
    final usesNarrationOnly = !_usesMacAutoscroll && Platform.isIOS;
    if (_usesMacAutoscroll || usesNarrationOnly) {
      _macAutoScroll = MacReaderAutoScrollController(
        scrollTarget: _scrollTarget,
        narrationControlsPacing:
            Platform.isMacOS || Platform.isAndroid || usesNarrationOnly,
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
    unawaited(_loadCitationResolver());
  }

  // Loaded once per reader session, app-wide: every detected reference is
  // checked against this before it is ever underlined, so a reference that
  // cannot resolve in the popup is never shown as if it could.
  Future<void> _loadCitationResolver() async {
    try {
      final db = StudyBibleDatabase.instance;
      final books = await db.loadBooks();
      final verseCounts = await db.loadVerseCounts();
      if (!mounted) return;
      setState(() {
        _citationResolves = (book, locator) =>
            libraryCitationResolves(book, locator, books, verseCounts);
      });
    } catch (error) {
      // Fail closed: keep the book readable without underlining citations
      // that cannot be proven resolvable in the installed Bible.
      debugPrint('Canonical citation resolver unavailable: $error');
      if (mounted) setState(() => _citationResolves = (_, _) => false);
    }
  }

  // The list only reports `_latestVisibleOrder` reactively, once its scroll
  // position listener fires after layout. Setting it here too, as soon as
  // the reader's opening/saved/search-target position is decided, means a
  // toolbar action (Contents, jump-to-heading) taken before that first
  // listener callback still reflects where the reader is actually about to
  // land, rather than the field's stale `0` default.
  void _setInitialSearchOrder(int order) {
    _initialSearchOrder = order;
    _latestVisibleOrder = order;
  }

  Future<void> _initializeAtSearchTarget() async {
    final target = widget.searchTarget;
    if (target == null) {
      debugPrint(
        'default_open_resolution_started workId=${widget.item.id} '
        'sourceEditionId=${widget.item.sourceWorkId ?? widget.item.id}',
      );
      final savedAnchor = widget.item.anchorId ?? '';
      final savedOrder = widget.item.lastOpened == null
          ? null
          : savedAnchor.startsWith('canonical:')
          ? await widget.repository.displayOrderForBlockId(
              widget.item.id,
              savedAnchor.substring('canonical:'.length),
            )
          : widget.item.paragraphIndex;
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
        _setInitialSearchOrder(savedOrder);
        await _controller.initialize(centerOrder: savedOrder);
        // `_controller.initialize` only settles once the window around
        // `savedOrder` is loaded, so the placeholder-free mount trick below
        // (see the opening-order branch) is safe to apply here too.
        if (!mounted) return;
        setState(() => _contentsJumpOrder = savedOrder);
        return;
      }
      // Leave `_initialSearchOrder` null when there's no substantive
      // section (the list keeps its natural top-of-book resting position),
      // but `_latestVisibleOrder` should still reflect that resting
      // position rather than an unrelated leftover value.
      _initialSearchOrder = openingOrder;
      _latestVisibleOrder = openingOrder ?? 0;
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
      // The list's very first build happens before this async resolution
      // completes, so it mounts at index 0 with itemCount 0. By the time
      // `openingOrder` is known and its window is loaded, that same
      // `ScrollablePositionedList` instance is already live with every
      // front-matter block between index 0 and `openingOrder` still an
      // unmeasured zero-height placeholder — a live `jumpTo()` through that
      // long placeholder run cannot derive a stable absolute offset and
      // lands short, inside Chapter 1 rather than at its heading (the same
      // failure `_jumpToBlock`'s Contents-navigation fix addresses below).
      // Forcing a fresh mount via a new key, with the target window already
      // loaded, lets `ScrollablePositionedList`'s own `initialScrollIndex`
      // position it directly instead.
      if (openingOrder != null && mounted) {
        setState(() => _contentsJumpOrder = openingOrder);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _commands.jumpToOrder(openingOrder);
        });
      }
      return;
    }
    debugPrint('search_target_received ${target.diagnosticSummary}');
    final order = await widget.repository.displayOrderForSearchTarget(target);
    if (order == null) {
      debugPrint(
        'search_target_resolution_failed ${target.diagnosticSummary} '
        'reason=canonical source map did not resolve',
      );
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
    debugPrint(
      'search_target_section_loaded ${target.diagnosticSummary} order=$order',
    );
    await _controller.initialize(centerOrder: order);
    if (!mounted) return;
    // The body initially mounts while the async source-map lookup/controller
    // load is still empty. Recreate that list once, after the exact target
    // window exists, so its initialScrollIndex is applied to measured rows.
    // This mirrors the proven default-open remount without converting an
    // explicit target into a cover/first-chapter/saved-position fallback.
    setState(() {
      _setInitialSearchOrder(order);
      _explicitTargetMountRevision += 1;
    });
  }

  void _visible(int order) {
    if (_macAutoScroll?.isNarrationMode == true &&
        _macAutoScroll!.isScrolling) {
      return;
    }
    _latestVisibleOrder = order;
    _controller.ensureWindow(order);
    // Desktop termination does not guarantee widget disposal. Save progress
    // during reading as well as on exit, using the stable canonical block ID.
    _positionSaveTimer ??= Timer(const Duration(seconds: 1), () {
      _positionSaveTimer = null;
      unawaited(_saveCurrentLocation());
    });
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
    _positionSaveTimer?.cancel();
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
    // Prefer the synchronously-tracked scroll position over `_location`,
    // which is debounced by 400ms and can lag behind on quick exits.
    final block = _controller.blockAt(_latestVisibleOrder) ?? _location?.block;
    if (block == null) return;
    _positionSave = _positionSave.then(
      (_) => LibraryReaderStateWriter.instance.saveCurrentLocation(
        libraryItemId: widget.item.id,
        currentSectionEntryName: block.sourceHref ?? block.sectionId,
        currentSectionSpineIndex: null,
        savedHref: block.sourceHref,
        savedAnchorId: 'canonical:${block.id}',
        savedParagraphIndex: block.displayOrder,
      ),
    );
    await _positionSave;
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
                    key: ValueKey<String>(
                      'canonical-body-$_explicitTargetMountRevision-'
                      '${_contentsJumpOrder ?? 'initial'}',
                    ),
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
                    onReaderInteraction: () {
                      _readerFocusNode.requestFocus();
                      _macAutoScroll?.pauseNarrationForInteraction();
                    },
                    narrationBlockId: _spokenBlockId,
                    onParagraphTap: (order) {
                      setState(() => _selectedRecordedCursor = '$order');
                    },
                    sourceRoot: widget.sourceRoot,
                    diagnostics: widget.diagnostics,
                    proofCommands: _commands,
                    speechFollow: _speechFollow,
                    fontScale: _fontScale,
                    showRefCodes: _showRefCodes,
                    referenceLinkingEnabled: _citationResolves != null,
                    citationResolves: _citationResolves,
                    highlightTerms: widget.highlightTerms,
                    initialScrollOrder:
                        _contentsJumpOrder ?? _initialSearchOrder,
                    alignFlush: _contentsJumpOrder != null,
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
                    markupsByBlockId: {
                      for (final entry in _canonicalHighlights.entries)
                        entry.key.substring('canonical:'.length): entry.value,
                    },
                    onSelectionChanged: (block, selection) {
                      if (!selection.isCollapsed) {
                        _selectedMarkupBlock = block;
                        _selectedMarkupRange = selection;
                      }
                    },
                    onOpenSelectionMenu: _openCanonicalSelectionMenu,
                    onFollowLink: (block, href) =>
                        unawaited(_followSourceLink(block, href)),
                  ),
                ),
              ),
              if ((Platform.isMacOS || Platform.isIOS) &&
                  _macAutoScroll != null)
                LibrarySpeechControls(
                  tiltController: _autoScroll,
                  controller: _macAutoScroll!,
                  bookId: widget.item.id,
                  title: widget.item.title,
                  author: widget.item.author,
                  initialCursor: () => '$_latestVisibleOrder',
                  load: _loadSpeechItem,
                  reveal: _revealSpeechItem,
                  revealRecorded: (item) =>
                      _revealSpeechItem(item, recorded: true),
                  recordedStartCursor: '0',
                  selectedRecordedCursor: () => _selectedRecordedCursor,
                  onPaused: () {
                    if (mounted) setState(() => _spokenBlockId = null);
                  },
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
              _autoScroll.isActive ||
              (_macAutoScroll?.isPixelScrolling ?? false),
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

  Future<LibrarySpeechItem?> _loadSpeechItem(String cursor) async {
    for (
      var order = int.parse(cursor);
      order < _controller.blockCount;
      order++
    ) {
      // Speech indexing must not depend on the viewport's coalesced window
      // requests: scrolling can replace the pending audio destination.
      var block = _controller.blockAt(order);
      if (block == null) {
        final rows = await widget.repository.loadWindow(
          widget.item.id,
          centerOrder: order,
          radius: 0,
        );
        if (!mounted) return null;
        block = rows.isEmpty ? null : rows.first;
      }
      if (block == null) {
        throw StateError('A book text block could not be loaded.');
      }
      if (block.blockType == LibraryDocumentBlockType.image ||
          block.blockType == LibraryDocumentBlockType.horizontalRule ||
          block.blockType == LibraryDocumentBlockType.unsupported ||
          block.plainText.trim().isEmpty) {
        continue;
      }
      return LibrarySpeechItem(
        cursor: '$order',
        nextCursor: '${order + 1}',
        text: block.plainText,
      );
    }
    return null;
  }

  Future<void> _revealSpeechItem(
    LibrarySpeechItem item, {
    bool recorded = false,
  }) async {
    if (!mounted) return;
    final order = int.parse(item.sourceCursor);
    if (recorded) await _controller.ensureNavigationWindow(order);
    if (!mounted) return;
    if (item.startOffset > 0) {
      // Later slices of a long paragraph: keep the spoken part on screen.
      if (recorded || _macAutoScroll?.isScrolling == true) {
        unawaited(
          _speechFollow.follow(
            order,
            librarySpeechProgress(item.startOffset, item.sourceLength),
          ),
        );
      }
      return;
    }
    final block = _controller.blockAt(order);
    setState(() {
      _spokenBlockId = block?.id;
      _latestVisibleOrder = order;
    });
    unawaited(_saveCurrentLocation());
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && (recorded || _macAutoScroll?.isScrolling == true)) {
      _commands.jumpToOrder(order);
    }
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
          audioEnabled: controller.audioEnabled,
          speechRate: controller.speechRate,
          announceChapter: controller.announceChapter,
          announceVerseNumbers: controller.announceVerseNumbers,
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
      audioEnabled: controller.audioEnabled,
      speechRate: controller.speechRate,
      announceChapter: controller.announceChapter,
      announceVerseNumbers: controller.announceVerseNumbers,
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
    unawaited(
      toggleSilentReaderTilt(tilt: _autoScroll, speech: _macAutoScroll),
    );
  }

  Future<void> _openTiltAutoscrollSettings() async {
    _macAutoScroll?.stopForManualInteraction();
    await _autoScroll.stop();
    if (!mounted) return;
    await showReaderTiltSettingsSheet(
      context,
      speechController: _macAutoScroll,
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
    unawaited(_saveCurrentLocation());
    _autoScroll.stop(notify: false);
    final narration = _macAutoScroll;
    // iOS keeps narrating behind a locked screen; stopping here would end it.
    if (narration != null && librarySpeechSurvivesBackground(narration)) return;
    narration?.stopForManualInteraction();
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
    final destinations = await widget.repository
        .loadCanonicalNavigationDestinations(widget.item.id);
    // EPUBs with no usable nav document still expose their semantic headings;
    // those headings are canonical blocks, not a second parser or fallback.
    final entries = destinations.isNotEmpty
        ? destinations
        : (await widget.repository.loadHeadings(widget.item.id))
              .map(
                (block) => LibraryCanonicalNavigationDestination(
                  id: block.id,
                  parentId: null,
                  label: block.plainText,
                  depth: switch (block.headingRole) {
                    'section' => 1,
                    'minor' => 2,
                    _ => 0,
                  },
                  block: block,
                ),
              )
              .toList(growable: false);
    if (!mounted) return;
    // Use the synchronously-tracked scroll position rather than `_location`,
    // which is only updated after a 400ms debounce and can still point at
    // the previous chapter if Contents is opened right after scrolling.
    final current = entries
        .where((entry) => entry.block.displayOrder <= _latestVisibleOrder)
        .lastOrNull;
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contents'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: entries
                .map(
                  (entry) => Padding(
                    padding: EdgeInsets.only(left: entry.depth * 16.0),
                    child: ListTile(
                      selected: entry.id == current?.id,
                      selectedTileColor: theme.colorScheme.primary.withValues(
                        alpha: 0.12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: entry.id == current?.id
                            ? BorderSide(
                                color: theme.colorScheme.primary,
                                width: 3,
                              )
                            : BorderSide.none,
                      ),
                      title: Text(
                        entry.label,
                        style: entry.id == current?.id
                            ? TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(_jumpToBlock(entry.block));
                      },
                    ),
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
  final LibrarySpeechFollowHandle _speechFollow = LibrarySpeechFollowHandle();

  Future<void> _jumpToBlock(LibraryDocumentBlock block) async {
    await _controller.ensureNavigationWindow(block.displayOrder);
    // `ensureWindow` settles only after any coalesced pending request has
    // loaded, so this check prevents a virtualized-list jump into a
    // zero-height placeholder while its real row is still arriving.
    if (!mounted || _controller.blockAt(block.displayOrder) == null) return;
    // Decode an image destination before positioning its virtualized row.
    // Otherwise its initial zero-height layout can move the saved reading
    // location to the following paragraph before the illustration arrives.
    if (block.blockType == LibraryDocumentBlockType.image &&
        widget.sourceRoot != null) {
      final formatted = LibraryFormattedContent.fromJson(
        block.formattedContent,
      );
      for (final node in formatted.nodes) {
        if (node['type'] != 'image') continue;
        final resolved = resolveCanonicalLocalImage(
          sourceRoot: widget.sourceRoot!,
          source: node['source']?.toString() ?? '',
        );
        if (resolved.status == CanonicalLocalImageStatus.resolved) {
          try {
            final image = await loadCanonicalReaderImage(resolved.file!);
            if (!mounted) return;
            await precacheImage(image.provider, context, onError: (_, _) {});
          } on FormatException {
            // Still navigate to the row so its visible fallback explains the failure.
          } on FileSystemException {
            // The image widget supplies the missing-file fallback.
          }
        }
        break;
      }
      if (!mounted) return;
    }
    // Recreate the virtualized list with the loaded target as its initial
    // index. `ScrollablePositionedList` cannot derive a stable absolute
    // offset through a long run of zero-height cache placeholders, even once
    // a later imperative jump is issued.
    setState(() => _contentsJumpOrder = block.displayOrder);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _commands.jumpToOrder(block.displayOrder);
    });
  }

  Future<void> _followSourceLink(
    LibraryDocumentBlock origin,
    String href,
  ) async {
    if (href.startsWith('studybible-citation:')) {
      final citation = Uri.tryParse(href);
      if (citation == null) return;
      _autoScroll.stopForManualInteraction();
      _macAutoScroll?.stopForManualInteraction();
      await showLibraryVersePopup(
        context,
        Uri.decodeComponent(citation.path),
        _fontScale,
      );
      return;
    }
    final target = await widget.repository.resolveSourceLink(
      widget.item.id,
      fromHref: origin.sourceHref ?? '',
      href: href,
    );
    if (!mounted) return;
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "This link’s destination isn’t available in this copy.",
          ),
        ),
      );
      return;
    }
    _selectedMarkupBlock = null;
    _selectedMarkupRange = null;
    await _jumpToBlock(target);
  }

  Future<void> _jumpHeading(bool forward) async {
    final current = _latestVisibleOrder;
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

  Future<void> _highlightCanonicalSelection({bool underline = false}) async {
    final block = _selectedMarkupBlock;
    final range = _selectedMarkupRange;
    if (block == null || range == null || range.isCollapsed) return;
    final start = range.start.clamp(0, block.plainText.length);
    final end = range.end.clamp(start, block.plainText.length);
    if (end <= start) return;
    final color = underline
        ? '#F7D87D'
        : await showElibraryHighlightColorPicker(context);
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
      markupType: underline
          ? ElibraryMarkupRepository.underlineType
          : ElibraryMarkupRepository.highlightType,
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
    final reference = canonicalSelectionReference(widget.item, block);
    final action = await showLibrarySelectionRangeActionsSheet(
      context,
      payload: LibrarySelectionRangeActionsPayload(
        referenceLabel: reference,
        previewText: selectedText,
        enableClearMarkup:
            _canonicalHighlights['canonical:${block.id}']?.any(
              (m) => m.startCharOffset < end && m.endCharOffset > start,
            ) ??
            false,
      ),
      fontScale: _fontScale,
      showRichCopy: false,
      showUnderline: true,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case LibrarySelectionRangeAction.copyNoCitation:
      case LibrarySelectionRangeAction.copyWithMarkup:
        await Clipboard.setData(
          ClipboardData(text: buildLibrarySelectionClipboardText(selectedText)),
        );
        return;
      case LibrarySelectionRangeAction.copyWithCitation:
      case LibrarySelectionRangeAction.copyWithMarkupAndCitation:
        await Clipboard.setData(
          ClipboardData(
            text: buildLibrarySelectionClipboardText(
              selectedText,
              referenceLabel: reference,
            ),
          ),
        );
        return;
      case LibrarySelectionRangeAction.addHashTag:
      case LibrarySelectionRangeAction.chooseHashTag:
        final tags = HashTagRepository();
        Future<HashTagQuickApplyResult> apply(String tag) =>
            saveCanonicalSelectionToTag(
              repository: widget.repository,
              tags: tags,
              item: widget.item,
              block: block,
              start: start,
              end: end,
              tag: tag,
            );
        if (action == LibrarySelectionRangeAction.addHashTag) {
          final defaultTag = tags.normalizeTagName(
            await tags.loadDefaultTag() ?? '',
          );
          if (!mounted) return;
          if (defaultTag.isNotEmpty) {
            final result = await apply(defaultTag);
            if (!mounted) return;
            if (result.tag != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    result.inserted > 0
                        ? 'Added selected range to ${result.tag}.'
                        : 'This range is already in ${result.tag}.',
                  ),
                ),
              );
              return;
            }
          }
        }
        if (!mounted) return;
        await showHashTagScreen(
          Navigator.of(context),
          passage: PassageData(
            bookNumber: null,
            bookName: widget.item.displayTitle,
            chapter: 0,
            lines: const <VerseLine>[],
          ),
          selection: const ViewerRangeSelection(),
          selectionTargets: const <HashTagTarget>[],
          fontScale: _fontScale,
          selectionLabelOverride: reference,
          onApplySelectionOverride: apply,
        );
        return;
      case LibrarySelectionRangeAction.highlight:
        await _highlightCanonicalSelection();
        return;
      case LibrarySelectionRangeAction.underline:
        await _highlightCanonicalSelection(underline: true);
        return;
      case LibrarySelectionRangeAction.clearMarkup:
        await ElibraryMarkupRepository().clearHighlightsOverlappingSelection(
          libraryItemId: widget.item.id,
          epubHref: 'canonical:${block.id}',
          startBlockIndex: 0,
          startCharOffset: start,
          endBlockIndex: 0,
          endCharOffset: end,
          includeUnderlines: true,
        );
        await _loadCanonicalHighlights();
        return;
      case LibrarySelectionRangeAction.resetRange:
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
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[back, title],
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
    this.speechFollow,
    this.fontScale = 1,
    this.onReaderInteraction,
    this.showRefCodes = false,
    this.referenceLinkingEnabled = false,
    this.citationResolves,
    this.highlightTerms = const <String>[],
    this.initialScrollOrder,
    this.alignFlush = false,
    this.onInitialScrollCompleted,
    this.highlightedBlockIds = const <String>{},
    this.narrationBlockId,
    this.onParagraphTap,
    this.markupsByBlockId = const <String, List<ElibraryMarkupRecord>>{},
    this.onSelectionChanged,
    this.onOpenSelectionMenu,
    this.onFollowLink,
  });
  final LibraryDocumentController controller;
  final CallbackReaderAutoScrollTarget autoScrollTarget;
  final ValueChanged<int> onVisibleOrderChanged;
  final Color textColor;
  final VoidCallback? onManualScroll;
  final Directory? sourceRoot;
  final CanonicalScrollDiagnostics? diagnostics;
  final CanonicalLibraryProofCommands? proofCommands;
  final LibrarySpeechFollowHandle? speechFollow;
  final double fontScale;
  final VoidCallback? onReaderInteraction;
  final bool showRefCodes;
  // True once the citation resolver has finished loading for this reader
  // session; false only during that brief startup window.
  final bool referenceLinkingEnabled;
  final bool Function(String book, String locator)? citationResolves;
  final List<String> highlightTerms;
  final int? initialScrollOrder;
  // Contents-jump, saved-position resume, and the front-matter-skip first
  // open all want the target heading flush against the top of the list
  // (alignment 0); an explicit search-target open instead wants a little
  // context visible above the match (alignment 0.08).
  final bool alignFlush;
  final VoidCallback? onInitialScrollCompleted;
  final Set<String> highlightedBlockIds;
  final String? narrationBlockId;
  final ValueChanged<int>? onParagraphTap;
  final Map<String, List<ElibraryMarkupRecord>> markupsByBlockId;
  final void Function(LibraryDocumentBlock block, TextSelection selection)?
  onSelectionChanged;
  final VoidCallback? onOpenSelectionMenu;
  final void Function(LibraryDocumentBlock block, String href)? onFollowLink;

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
      widget.speechFollow?.attach(_followSpeech);
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
    _itemController.jumpTo(
      index: order,
      alignment: widget.alignFlush ? 0 : 0.08,
    );
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
      alignment: 0,
    );
  }

  Future<bool> _followSpeech(int order, double progress) async {
    final position = _position;
    if (position == null || !position.hasPixels) return false;
    for (final item in _positions.itemPositions.value) {
      if (item.index != order) continue;
      final sliceDelta = librarySpeechFollowDelta(
        sliceTop:
            (item.itemLeadingEdge +
                progress * (item.itemTrailingEdge - item.itemLeadingEdge)) *
            position.viewportDimension,
        viewportHeight: position.viewportDimension,
      );
      final spokenTop =
          (item.itemLeadingEdge +
              progress * (item.itemTrailingEdge - item.itemLeadingEdge)) *
          position.viewportDimension;
      final delta = spokenTop - position.viewportDimension * .35;
      return delta > 1
          ? await animateSpeechFollow(
              position,
              delta,
              duration: const Duration(milliseconds: 400),
              curve: Curves.linear,
            )
          : sliceDelta != null && sliceDelta < 0
          ? await animateSpeechFollow(position, sliceDelta)
          : false;
    }
    // A phrase may begin in a block that is not currently on screen.
    // Bring that block into view instead of silently dropping the update.
    _itemController.jumpTo(
      index: order.clamp(0, widget.controller.blockCount - 1),
      alignment: librarySpeechAnchor,
    );
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return false;
    for (final item in _positions.itemPositions.value) {
      if (item.index != order) continue;
      final sliceDelta = librarySpeechFollowDelta(
        sliceTop:
            (item.itemLeadingEdge +
                progress * (item.itemTrailingEdge - item.itemLeadingEdge)) *
            position.viewportDimension,
        viewportHeight: position.viewportDimension,
      );
      final spokenTop =
          (item.itemLeadingEdge +
              progress * (item.itemTrailingEdge - item.itemLeadingEdge)) *
          position.viewportDimension;
      final delta = spokenTop - position.viewportDimension * .35;
      return delta > 1
          ? await animateSpeechFollow(
              position,
              delta,
              duration: const Duration(milliseconds: 400),
              curve: Curves.linear,
            )
          : sliceDelta != null && sliceDelta < 0
          ? await animateSpeechFollow(position, sliceDelta)
          : false;
    }
    return false;
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
    widget.speechFollow?.detach();
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
                initialAlignment:
                    widget.initialScrollOrder == null || widget.alignFlush
                    ? 0
                    : 0.08,
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
                  return Listener(
                    onPointerUp: (_) => widget.onParagraphTap?.call(order),
                    child: Container(
                      key: ValueKey(block.id),
                      color: widget.narrationBlockId == block.id
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: .16)
                          : null,
                      child: _CanonicalBlockView(
                        block: block,
                        color: widget.textColor,
                        sourceRoot: widget.sourceRoot,
                        fontScale: widget.fontScale,
                        showRefCode: widget.showRefCodes,
                        referenceLinkingEnabled: widget.referenceLinkingEnabled,
                        citationResolves: widget.citationResolves,
                        highlightTerms: widget.highlightTerms,
                        markups: widget.markupsByBlockId[block.id] ?? const [],
                        onSelectionChanged: (selection) =>
                            widget.onSelectionChanged?.call(block, selection),
                        onOpenSelectionMenu: widget.onOpenSelectionMenu,
                        onFollowLink: widget.onFollowLink == null
                            ? null
                            : (href) => widget.onFollowLink!(block, href),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
}

class _CanonicalBlockView extends StatefulWidget {
  const _CanonicalBlockView({
    required this.block,
    required this.color,
    required this.sourceRoot,
    required this.fontScale,
    required this.showRefCode,
    this.referenceLinkingEnabled = false,
    this.citationResolves,
    this.highlightTerms = const <String>[],
    this.markups = const [],
    required this.onSelectionChanged,
    required this.onOpenSelectionMenu,
    this.onFollowLink,
  });
  final LibraryDocumentBlock block;
  final Color color;
  final Directory? sourceRoot;
  final double fontScale;
  final bool showRefCode;
  final bool referenceLinkingEnabled;
  final bool Function(String book, String locator)? citationResolves;
  final List<String> highlightTerms;
  final List<ElibraryMarkupRecord> markups;
  final ValueChanged<TextSelection>? onSelectionChanged;
  final VoidCallback? onOpenSelectionMenu;
  final ValueChanged<String>? onFollowLink;

  @override
  State<_CanonicalBlockView> createState() => _CanonicalBlockViewState();
}

class _CanonicalBlockViewState extends State<_CanonicalBlockView> {
  final _linkRecognizers = <String, TapGestureRecognizer>{};
  var _hasSelection = false;

  GestureRecognizer? _recognizer(String href) {
    if (widget.onFollowLink == null ||
        !canonicalReaderSupportsLink(widget.block.sourceHref ?? '', href)) {
      return null;
    }
    return _linkRecognizers.putIfAbsent(
      href,
      () => TapGestureRecognizer()
        ..onTap = () {
          // A selected range belongs to the annotation flow; dragging or a long
          // press on a linked number must not unexpectedly navigate away.
          if (!_hasSelection) widget.onFollowLink?.call(href);
        },
    );
  }

  @override
  void didUpdateWidget(covariant _CanonicalBlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.id != widget.block.id ||
        oldWidget.block.formattedContent != widget.block.formattedContent) {
      for (final recognizer in _linkRecognizers.values) {
        recognizer.dispose();
      }
      _linkRecognizers.clear();
      _hasSelection = false;
    }
  }

  @override
  void dispose() {
    for (final recognizer in _linkRecognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block, color = widget.color;
    final sourceRoot = widget.sourceRoot, fontScale = widget.fontScale;
    final showRefCode = widget.showRefCode,
        highlightTerms = widget.highlightTerms;
    final markups = widget.markups;
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
          : resolveCanonicalLocalImage(sourceRoot: sourceRoot, source: source);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: resolution.status == CanonicalLocalImageStatus.resolved
            ? CanonicalReaderImage(
                file: resolution.file!,
                rotationDegrees:
                    imageNode?['rotation_degrees'] is int &&
                        const [
                          0,
                          90,
                          180,
                          270,
                        ].contains(imageNode?['rotation_degrees'])
                    ? imageNode!['rotation_degrees'] as int
                    : 0,
                semanticLabel: block.plainText.isEmpty ? null : block.plainText,
                errorBuilder: (_, _, _) =>
                    _CanonicalImageFallback(color: color, alt: block.plainText),
              )
            : _CanonicalImageFallback(color: color, alt: block.plainText),
      );
    }
    final heading = block.blockType == LibraryDocumentBlockType.heading;
    final outline = formatted.metadata['content_role'] == 'chapter_outline';
    final quotation = block.blockType == LibraryDocumentBlockType.quotation;
    final poem = block.blockType == LibraryDocumentBlockType.poem;
    final relativeSize = formatted.metadata['relative_font_scale'];
    final blockFontScale = relativeSize is num && relativeSize.isFinite
        ? relativeSize.clamp(0.7, 2.0).toDouble()
        : 1.0;
    final base = TextStyle(
      color: color,
      fontSize:
          (formatted.metadata['font_scale_basis'] == 'body'
              ? 18
              : heading
              ? 24
              : outline
              ? 16
              : 18) *
          fontScale *
          blockFontScale,
      height: heading ? 1.3 : 1.6,
      fontWeight: heading ? FontWeight.w800 : FontWeight.w400,
      fontStyle: quotation ? FontStyle.italic : null,
    );
    final align = switch (formatted.alignment) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      'end' => TextAlign.end,
      _ => TextAlign.start,
    };
    final tableRows = formatted.metadata['table_rows'];
    if (tableRows is List && tableRows.isNotEmpty) {
      final rows = tableRows
          .map(
            (row) => (row as List)
                .map((cell) => Map<String, Object?>.from(cell as Map))
                .toList(),
          )
          .toList();
      final columns = rows
          .map(
            (row) => row.fold<int>(
              0,
              (sum, cell) => sum + (cell['colspan'] as int? ?? 1),
            ),
          )
          .reduce((a, b) => a > b ? a : b);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minWidth = columns > 2 ? columns * 150.0 * fontScale : 0.0;
            final width = constraints.maxWidth < minWidth
                ? minWidth
                : constraints.maxWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows
                      .map(
                        (row) => IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final cell in row)
                                SizedBox(
                                  width:
                                      width *
                                      (cell['colspan'] as int? ?? 1) /
                                      columns,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: color.withValues(alpha: .45),
                                      ),
                                    ),
                                    child: SelectableText.rich(
                                      TextSpan(
                                        style: base,
                                        children: canonicalInlineTextSpans(
                                          block: block,
                                          formatted: LibraryFormattedContent(
                                            nodes: (cell['nodes'] as List)
                                                .map(
                                                  (node) =>
                                                      Map<String, Object?>.from(
                                                        node as Map,
                                                      ),
                                                )
                                                .toList(),
                                          ),
                                          bodyStyle: cell['header'] == true
                                              ? base.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                )
                                              : base,
                                          referenceStyle: base,
                                          showReferenceCode: false,
                                          highlightTerms: highlightTerms,
                                          linkRecognizer:
                                              widget.referenceLinkingEnabled
                                              ? _recognizer
                                              : null,
                                          citationResolves:
                                              widget.citationResolves,
                                        ),
                                      ),
                                      textAlign: switch (cell['alignment']) {
                                        'center' => TextAlign.center,
                                        'right' => TextAlign.right,
                                        'justify' => TextAlign.justify,
                                        'end' => TextAlign.end,
                                        'left' || 'start' => TextAlign.start,
                                        _ =>
                                          cell['header'] == true
                                              ? TextAlign.center
                                              : TextAlign.start,
                                      },
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            );
          },
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        top: formatted.metadata['compact_centered_paragraph'] == true
            ? 0
            : heading
            ? 20
            : 6,
        bottom: formatted.metadata['compact_centered_paragraph'] == true
            ? 0
            : heading
            ? 12
            : 14,
        left: quotation ? 12 : 0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.transparent,
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
                    fontSize: base.fontSize! * .72,
                    color: color.withValues(alpha: .65),
                    fontWeight: FontWeight.w500,
                  ),
                  showReferenceCode: showRefCode,
                  highlightTerms: highlightTerms,
                  markups: markups,
                  linkRecognizer: widget.referenceLinkingEnabled
                      ? _recognizer
                      : null,
                  citationResolves: widget.citationResolves,
                ),
              ),
              textAlign: align,
              style: poem ? base.copyWith(fontFamily: 'monospace') : base,
              onSelectionChanged: (selection, _) {
                _hasSelection = !selection.isCollapsed;
                widget.onSelectionChanged?.call(selection);
              },
              onTap: widget.onOpenSelectionMenu,
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
