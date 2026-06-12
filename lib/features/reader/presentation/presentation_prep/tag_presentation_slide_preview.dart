import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../core/bootstrap/library_root_service.dart';
import '../../../../core/database/study_bible_database.dart';
import '../../../../features/library/data/library_citation_display_helper.dart';
import '../../data/tags/unified_tag_models.dart';
import 'tag_presentation_auto_fit_text.dart';
import 'tag_presentation_media_path_resolver.dart';
import 'tag_presentation_prep_models.dart';
import 'tag_presentation_prep_state.dart';
import 'tag_prepared_slide_renderer.dart';

Future<void> showTagPresentationSlidePreview(
  BuildContext context, {
  required TagPresentationPrepWorkspace workspace,
}) async {
  if (!context.mounted) return;
  final previewWorkspace = TagPresentationPrepWorkspace.fromPreview(
    workspace.snapshot(),
  );
  if (previewWorkspace.slides.isNotEmpty) {
    previewWorkspace.selectedSlideIndex = workspace.selectedSlideIndex.clamp(
      0,
      previewWorkspace.slides.length - 1,
    );
  }
  previewWorkspace.selectedItemId = workspace.selectedItemId;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close slide preview',
    barrierColor: Colors.black.withValues(alpha: 0.94),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return TagPresentationSlidePreview(workspace: previewWorkspace);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.988, end: 1.0).animate(fade),
          child: child,
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Shared slide-content builder — used by both Preview and Run screen
// ---------------------------------------------------------------------------

/// Shared data needed to render any slide in a presentation.
/// Load once via [loadPresentationSharedData] and reuse across slides.
class PresentationSharedData {
  const PresentationSharedData({
    required this.bookNames,
    required this.mediaRoots,
  });

  final Map<int, String> bookNames;
  final List<String> mediaRoots;
}

/// Loads book names and media root paths once for a full presentation run.
Future<PresentationSharedData> loadPresentationSharedData() async {
  final mediaRootPath = await LibraryRootService.instance
      .accessibleLibraryRootPath();
  final mediaRoots =
      await TagPresentationMediaPathResolver.collectRootCandidates(
        preferredRootPath: mediaRootPath,
      );
  final books = await StudyBibleDatabase.instance.loadBooks();
  return PresentationSharedData(
    bookNames: {for (final book in books) book.bookNumber: book.bookName},
    mediaRoots: mediaRoots,
  );
}

/// Builds the item widget map for [slide] using the same visual rendering
/// as Preview. Pass the result to [TagPreparedSlideRenderer.itemWidgetsById].
Future<Map<String, Widget>> buildPresentationSlideWidgets({
  required TagPresentationPrepSlide slide,
  required TagPresentationPrepWorkspace workspace,
  required PresentationSharedData sharedData,
}) async {
  final result = <String, Widget>{};
  for (final itemId in slide.gridLayout.assignedItemIds) {
    final item = workspace.itemById(itemId);
    if (item == null) continue;
    final resolved = await _resolveItemForPreview(
      item: item,
      bookNames: sharedData.bookNames,
    );
    result[itemId] = _PreviewItemCard(
      item: resolved,
      mediaRoots: sharedData.mediaRoots,
    );
  }
  return result;
}

class TagPresentationSlidePreview extends StatefulWidget {
  const TagPresentationSlidePreview({super.key, required this.workspace});

  final TagPresentationPrepWorkspace workspace;

  @override
  State<TagPresentationSlidePreview> createState() =>
      _TagPresentationSlidePreviewState();
}

class _TagPresentationSlidePreviewState
    extends State<TagPresentationSlidePreview> {
  late final Future<_PreviewSlideData> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadPreviewData();
  }

  Future<_PreviewSlideData> _loadPreviewData() async {
    final selectedSlide = widget.workspace.selectedSlide;
    if (selectedSlide == null) {
      return _PreviewSlideData.empty();
    }

    final mediaRootPath = await LibraryRootService.instance
        .accessibleLibraryRootPath();
    final mediaRoots =
        await TagPresentationMediaPathResolver.collectRootCandidates(
          preferredRootPath: mediaRootPath,
        );
    final books = await StudyBibleDatabase.instance.loadBooks();
    final bookNames = <int, String>{
      for (final book in books) book.bookNumber: book.bookName,
    };

    final itemsById = <String, _PreviewResolvedItem>{};
    for (final itemId in selectedSlide.gridLayout.assignedItemIds) {
      final item = widget.workspace.itemById(itemId);
      if (item == null) continue;
      itemsById[item.id] = await _resolveItemForPreview(
        item: item,
        bookNames: bookNames,
      );
    }

    return _PreviewSlideData(
      bookNames: bookNames,
      itemsById: itemsById,
      mediaRoots: mediaRoots,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedSlide = widget.workspace.selectedSlide;
    return FutureBuilder<_PreviewSlideData>(
      future: _loadFuture,
      builder: (context, snapshot) {
        final previewData = snapshot.data ?? _PreviewSlideData.empty();
        return Scaffold(
          backgroundColor: const Color(0xFF050506),
          body: SafeArea(
            child: Stack(
              children: [
                const Positioned.fill(child: _PresentationBackdrop()),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                    child: ExcludeSemantics(
                      child: selectedSlide == null
                          ? const _EmptyPresentationSlide()
                          : snapshot.connectionState ==
                                    ConnectionState.waiting &&
                                snapshot.data == null
                          ? const _LoadingPresentationSlide()
                          : _PresentationPreviewStage(
                              selectedSlide: selectedSlide,
                              previewData: previewData,
                            ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: SafeArea(
                    minimum: const EdgeInsets.only(top: 4, right: 4),
                    child: Material(
                      color: const Color(0xAA141417),
                      borderRadius: BorderRadius.circular(999),
                      elevation: 4,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Close preview',
                        color: const Color(0xFFF3EFE4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreviewSlideData {
  const _PreviewSlideData({
    required this.bookNames,
    required this.itemsById,
    required this.mediaRoots,
  });

  const _PreviewSlideData.empty()
    : bookNames = const <int, String>{},
      itemsById = const <String, _PreviewResolvedItem>{},
      mediaRoots = const <String>[];

  final Map<int, String> bookNames;
  final Map<String, _PreviewResolvedItem> itemsById;
  final List<String> mediaRoots;
}

class _PreviewResolvedItem {
  const _PreviewResolvedItem({
    required this.itemType,
    required this.reference,
    required this.body,
    this.isPresentationTitle = false,
    this.secondary,
    this.caption,
    this.mediaPath,
  });

  final UnifiedTagItemType itemType;
  final String reference;
  final String? body;
  final bool isPresentationTitle;
  final String? secondary;
  final String? caption;
  final String? mediaPath;
}

Future<_PreviewResolvedItem> _resolveItemForPreview({
  required UnifiedTagChainItem item,
  required Map<int, String> bookNames,
}) async {
  switch (item.itemType) {
    case UnifiedTagItemType.bibleVerse:
    case UnifiedTagItemType.bibleRange:
    case UnifiedTagItemType.unknownLegacy:
      final bible = item.bibleAnchor;
      if (bible != null) {
        return _PreviewResolvedItem(
          itemType: item.itemType,
          reference: bible.displayReference(bookNames),
          body:
              await _loadBibleTextForAnchor(bible) ??
              _fallbackBibleBody(item) ??
              'Verse text unavailable.',
          secondary:
              _cleanText(item.noteText) ??
              _cleanText(item.elibraryAnchor?.excerpt) ??
              _cleanText(item.elibraryAnchor?.selectedTextSnapshot),
        );
      }
      return _PreviewResolvedItem(
        itemType: item.itemType,
        reference: _fallbackReference(item, fallbackLabel: 'Bible'),
        body: _fallbackBibleBody(item) ?? 'Verse text unavailable.',
        secondary: _cleanText(item.noteText),
      );
    case UnifiedTagItemType.eLibraryRange:
      return _PreviewResolvedItem(
        itemType: item.itemType,
        reference: _elibraryReference(item),
        body: _elibraryBody(item),
        secondary: _cleanText(item.noteText),
      );
    case UnifiedTagItemType.note:
      return _PreviewResolvedItem(
        itemType: item.itemType,
        reference: _fallbackReference(item, fallbackLabel: 'Note'),
        body: _noteBody(item),
        secondary: null,
      );
    case UnifiedTagItemType.image:
    case UnifiedTagItemType.media:
      return _PreviewResolvedItem(
        itemType: item.itemType,
        reference: _presentationLabelOrFallback(
          item.displayTitle,
          fallback: item.itemType == UnifiedTagItemType.image
              ? 'Image'
              : 'Media',
        ),
        body: _mediaPresentationBody(item),
        secondary: null,
        caption: _mediaPresentationCaption(item),
        mediaPath: item.media.isNotEmpty ? item.media.first.relativePath : null,
      );
    case UnifiedTagItemType.heading:
      return _PreviewResolvedItem(
        itemType: item.itemType,
        reference: _fallbackReference(item, fallbackLabel: 'Heading'),
        body: _fallbackText(item),
        secondary: _cleanText(item.noteText),
        isPresentationTitle: item.isPresentationTitle,
      );
  }
}

Future<String?> _loadBibleTextForAnchor(UnifiedTagBibleAnchor anchor) async {
  final start = anchor.verseStart;
  final end = math.max(anchor.verseStart, anchor.verseEnd);
  if (start <= 0 || end <= 0) return null;

  final verses = <String>[];
  for (var verse = start; verse <= end; verse++) {
    final text = await StudyBibleDatabase.instance.loadVerseText(
      bookNumber: anchor.bookNumber,
      chapter: anchor.chapter,
      verse: verse,
    );
    final cleaned = _cleanText(text);
    if (cleaned != null && cleaned.isNotEmpty) {
      verses.add(cleaned);
    }
  }
  if (verses.isEmpty) return null;
  return verses.join('\n');
}

String _fallbackReference(
  UnifiedTagChainItem item, {
  required String fallbackLabel,
}) {
  final bible = item.bibleAnchor;
  if (bible != null) {
    final verseRef = _cleanText(bible.verseRef);
    if (verseRef != null) return verseRef;
    final referenceCode = _cleanText(bible.referenceCode);
    if (referenceCode != null) return referenceCode;
  }

  final elibrary = item.elibraryAnchor;
  if (elibrary != null) {
    return libraryUserFacingELibraryDisplayLabel(
      sourceTitle: elibrary.sourceTitle ?? '',
      sourceTitleAcronym: elibrary.sourceTitleAcronym,
      sourceLocation: elibrary.sourceLocation,
      sourceReferenceText: elibrary.sourceReferenceText,
      fileName: elibrary.sourceRelativePath?.trim().isNotEmpty == true
          ? p.basename(elibrary.sourceRelativePath!)
          : null,
      relativePath: elibrary.sourceRelativePath,
      pageCitation:
          elibrary.sourcePageNumber != null &&
              elibrary.sourceParagraphNumber != null
          ? '${elibrary.sourcePageNumber}.${elibrary.sourceParagraphNumber}'
          : null,
      paragraphIndex:
          elibrary.sourceParagraphNumber ?? elibrary.sourceParagraphIndex,
    );
  }

  final title = _cleanText(item.displayTitle);
  if (title != null) return title;
  return fallbackLabel;
}

String? _fallbackBibleBody(UnifiedTagChainItem item) {
  final snapshot = _cleanText(item.textSnapshot);
  if (snapshot != null) return snapshot;
  final note = _cleanText(item.noteText);
  if (note != null) return note;
  final html = _cleanText(item.htmlContent);
  if (html != null) return _stripHtml(html);
  return null;
}

String _noteBody(UnifiedTagChainItem item) {
  final note = _cleanText(item.noteText);
  if (note != null) return note;
  final snapshot = _cleanText(item.textSnapshot);
  if (snapshot != null) return snapshot;
  final html = _cleanText(item.htmlContent);
  if (html != null) return _stripHtml(html);
  return 'No note text available.';
}

String _elibraryReference(UnifiedTagChainItem item) {
  final elibrary = item.elibraryAnchor;
  if (elibrary == null) return 'eLibrary';
  return libraryUserFacingELibraryCitationText(
    sourceTitle: elibrary.sourceTitle ?? '',
    sourceTitleAcronym: elibrary.sourceTitleAcronym,
    sourceLocation: elibrary.sourceLocation,
    sourceReferenceText: elibrary.sourceReferenceText,
    fileName: elibrary.sourceRelativePath?.trim().isNotEmpty == true
        ? p.basename(elibrary.sourceRelativePath!)
        : null,
    relativePath: elibrary.sourceRelativePath,
    pageCitation:
        elibrary.sourcePageNumber != null &&
            elibrary.sourceParagraphNumber != null
        ? '${elibrary.sourcePageNumber}.${elibrary.sourceParagraphNumber}'
        : null,
    paragraphIndex:
        elibrary.sourceParagraphNumber ?? elibrary.sourceParagraphIndex,
  );
}

String _elibraryBody(UnifiedTagChainItem item) {
  final elibrary = item.elibraryAnchor;
  if (elibrary == null) {
    return _fallbackText(item) ?? 'eLibrary content unavailable.';
  }

  final selectedText = _cleanText(elibrary.selectedTextSnapshot);
  if (selectedText != null) return selectedText;
  final excerpt = _cleanText(elibrary.excerpt);
  if (excerpt != null) return excerpt;
  final paragraph = _cleanText(elibrary.sourceParagraph);
  if (paragraph != null) return paragraph;
  final snapshot = _cleanText(item.textSnapshot);
  if (snapshot != null) return snapshot;
  final html = _cleanText(item.htmlContent);
  if (html != null) return _stripHtml(html);
  return 'eLibrary content unavailable.';
}

String? _mediaPresentationCaption(UnifiedTagChainItem item) {
  final displayTitle = _presentationLabelOrNull(item.displayTitle);
  if (displayTitle != null) return displayTitle;
  if (item.media.isEmpty) return null;
  // Only use an explicit user-set caption; never fall back to relativePath
  // since that would expose raw internal filenames.
  return _presentationLabelOrNull(item.media.first.caption);
}

String? _mediaPresentationBody(UnifiedTagChainItem item) {
  final note = _presentationFriendlyText(item.noteText);
  if (note != null) return note;
  final snapshot = _presentationFriendlyText(item.textSnapshot);
  if (snapshot != null) return snapshot;
  final html = _presentationFriendlyText(item.htmlContent);
  if (html != null) return _stripHtml(html);
  return null;
}

String? _fallbackText(UnifiedTagChainItem item) {
  final snapshot = _cleanText(item.textSnapshot);
  if (snapshot != null) return snapshot;
  final note = _cleanText(item.noteText);
  if (note != null) return note;
  final html = _cleanText(item.htmlContent);
  if (html != null) return _stripHtml(html);
  return null;
}

String? _cleanText(String? value) {
  final cleaned = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  return cleaned.isEmpty ? null : cleaned;
}

String? _presentationFriendlyText(String? value) {
  final cleaned = _cleanText(value);
  if (cleaned == null) return null;
  return _looksLikeTechnicalPresentationText(cleaned) ? null : cleaned;
}

String? _presentationLabelOrNull(String? value) {
  final cleaned = _cleanText(value);
  if (cleaned == null) return null;
  return _looksLikeTechnicalPresentationText(cleaned) ? null : cleaned;
}

String _presentationLabelOrFallback(String? value, {required String fallback}) {
  return _presentationLabelOrNull(value) ?? fallback;
}

bool _looksLikeTechnicalPresentationText(String text) {
  final lower = text.toLowerCase();
  // Exact generic fallback type labels are never real user captions.
  if (lower == 'image' || lower == 'media' || lower == 'attached' ||
      lower == 'attached image' || lower == 'attached media') {
    return true;
  }
  if (lower.startsWith('note:')) return true;
  if (lower.startsWith('content_')) return true;
  if (lower.startsWith('media_')) return true;
  if (lower.startsWith('file_')) return true;
  if (lower.startsWith('img_')) return true;
  if (lower.startsWith('hash:')) return true;
  // Path separators → internal path
  if (text.contains('/') || text.contains('\\')) return true;
  // file: / content: URI schemes
  if (lower.startsWith('file:') || lower.startsWith('content:')) return true;
  // Embedded content_<digits> anywhere (e.g. "Media: content_1781030663171_...")
  if (RegExp(r'content_\d{7,}').hasMatch(lower)) return true;
  if (lower.contains('tag_item_media')) return true;
  if (lower.contains('contentid') || lower.contains('noteid')) return true;
  if (lower.contains('selectedtextsnapshot')) return true;
  if (lower.contains('sourceparagraph')) return true;
  if (lower.contains('relativepath')) return true;
  // Long image filename with no spaces (hash/timestamp-derived)
  if (!text.contains(' ') &&
      text.length > 20 &&
      RegExp(r'\.(png|jpg|jpeg|gif|webp|bmp|heic)$').hasMatch(lower) &&
      RegExp(r'\d{8,}').hasMatch(text)) {
    return true;
  }
  if (RegExp(r'^[a-f0-9]{12,}$', caseSensitive: false).hasMatch(text)) {
    return true;
  }
  if (RegExp(
    r'^(note|content|media)[:_-]?\d+',
    caseSensitive: false,
  ).hasMatch(text)) {
    return true;
  }
  // Constructed type-prefix labels where the suffix is an internal filename,
  // e.g. "Image: content_1781030663171_..." or "Media: media_abc123..."
  for (final prefix in const ['image: ', 'media: ']) {
    if (lower.startsWith(prefix)) {
      final tail = text.substring(prefix.length);
      final tailLower = tail.toLowerCase();
      if (tailLower.startsWith('content_') ||
          tailLower.startsWith('media_') ||
          tailLower.startsWith('file_') ||
          tailLower.startsWith('img_') ||
          tailLower.startsWith('hash_') ||
          tailLower.startsWith('hash:') ||
          tail.contains('/') ||
          tail.contains('\\') ||
          RegExp(r'^[a-f0-9]{12,}$', caseSensitive: false).hasMatch(tail) ||
          RegExp(
            r'^(note|content|media)[:_-]?\d+',
            caseSensitive: false,
          ).hasMatch(tail)) {
        return true;
      }
    }
  }
  return false;
}

class _PresentationBackdrop extends StatelessWidget {
  const _PresentationBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.0, -0.2),
          radius: 1.2,
          colors: [Color(0xFF151518), Color(0xFF050506)],
          stops: [0.0, 1.0],
        ),
      ),
    );
  }
}

class _EmptyPresentationSlide extends StatelessWidget {
  const _EmptyPresentationSlide();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No slide selected',
        style: TextStyle(
          color: Color(0xFFF3EFE4),
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LoadingPresentationSlide extends StatelessWidget {
  const _LoadingPresentationSlide();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(strokeWidth: 2.8),
      ),
    );
  }
}

class _PresentationPreviewStage extends StatelessWidget {
  const _PresentationPreviewStage({
    required this.selectedSlide,
    required this.previewData,
  });

  final TagPresentationPrepSlide selectedSlide;
  final _PreviewSlideData previewData;

  @override
  Widget build(BuildContext context) {
    final itemWidgetsById = <String, Widget>{
      for (final itemId in selectedSlide.gridLayout.assignedItemIds)
        if (previewData.itemsById[itemId] != null)
          itemId: _PreviewItemCard(
            item: previewData.itemsById[itemId]!,
            mediaRoots: previewData.mediaRoots,
          ),
    };
    return TagPreparedSlideRenderer(
      slide: selectedSlide,
      itemWidgetsById: itemWidgetsById,
      aspectRatio: selectedSlide.aspectRatio.aspectRatio,
    );
  }
}

class _PreviewItemCard extends StatelessWidget {
  const _PreviewItemCard({required this.item, this.mediaRoots});

  final _PreviewResolvedItem item;
  final List<String>? mediaRoots;

  @override
  Widget build(BuildContext context) {
    if (item.isPresentationTitle) {
      return _PreviewTitlePanel(item: item);
    }
    return switch (item.itemType) {
      UnifiedTagItemType.note => _PreviewNotePanel(item: item),
      UnifiedTagItemType.image || UnifiedTagItemType.media =>
        _PreviewMediaPanel(item: item, mediaRoots: mediaRoots),
      UnifiedTagItemType.heading => _PreviewTextBlock(
        item: item,
        style: _PreviewTextStyle.heading,
      ),
      UnifiedTagItemType.bibleVerse ||
      UnifiedTagItemType.bibleRange ||
      UnifiedTagItemType.eLibraryRange ||
      UnifiedTagItemType.unknownLegacy => _PreviewTextBlock(
        item: item,
        style: _PreviewTextStyle.scripture,
      ),
    };
  }
}

class _PreviewTitlePanel extends StatelessWidget {
  const _PreviewTitlePanel({required this.item});

  final _PreviewResolvedItem item;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final inset = math.max(4.0, width * 0.012);
        final titleMax = math.min(
          30.0,
          math.max(12.0, math.min(width / 7.0, height * 0.42)),
        );
        return Padding(
          padding: EdgeInsets.all(inset),
          child: Center(
            child: TagPresentationAutoFitText(
              text: item.reference,
              style: const TextStyle(
                color: Color(0xFFF0D68A),
                fontWeight: FontWeight.w800,
                height: 1.06,
              ),
              minFontSize: 12,
              maxFontSize: titleMax,
              maxLines: 2,
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
}

class _PreviewTextBlock extends StatelessWidget {
  const _PreviewTextBlock({required this.item, required this.style});

  final _PreviewResolvedItem item;
  final _PreviewTextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final isHeading = style == _PreviewTextStyle.heading;
        final isScripture = style == _PreviewTextStyle.scripture;
        final bodyMax = _previewBodyMaxFontSize(
          item.body,
          width: width,
          height: height,
        );
        final bodyMin = isHeading ? 12.0 : 14.0;
        final secondaryText = _presentationFriendlyText(item.secondary);
        final inset = math.max(4.0, width * 0.012);

        if (isScripture) {
          // Scripture / eLibrary: measure body + secondary + reference as one
          // combined block. Iterate from maxFont down, taking the largest font
          // where the whole block fits — this maximises vertical fill
          // (target 55–85 %).  Reference scales with body so merged /
          // full-slide zones get a proportionally larger reference.
          final body = (item.body ?? '').trim();
          final hasSecondary = (secondaryText ?? '').trim().isNotEmpty;
          final availW = math.max(8.0, width - 2 * inset);
          final availH = math.max(8.0, height - 2 * inset);

          const bodyLineH = 1.20;
          const refLineH = 1.02;
          const minFont = 14.0;
          final maxFont = _scriptureBodyMaxFontSize(
            body,
            width: availW,
            height: availH,
          );

          // Secondary occupies a fixed-height slot regardless of body font.
          final secGapH = hasSecondary ? math.max(4.0, availH * 0.01) : 0.0;
          final secSlotH = hasSecondary
              ? math.max(14.0, math.min(18.0, availH * 0.08))
              : 0.0;

          // Reference font ceiling scales generously with zone height so that
          // merged / full-slide zones show a visibly larger reference.
          // Scale factor raised to 0.55 and hard cap raised to 54.
          final refScaleMax = math.max(22.0, math.min(availH * 0.15, 54.0));
          var bestFont = minFont;
          for (var fs = maxFont; fs >= minFont; fs -= 1.0) {
            final rfs = (fs * 0.55).clamp(13.0, refScaleMax);
            final gap = math.max(4.0, math.min(fs * 0.28, 22.0));
            final bH = body.isNotEmpty
                ? (_makePainterForFit(body, fs, bodyLineH)
                      ..layout(maxWidth: availW))
                    .height
                : 0.0;
            final rH = (_makePainterForFit(
                  item.reference,
                  rfs,
                  refLineH,
                  maxLines: 1,
                )..layout(maxWidth: availW))
                .height;
            if (bH + secGapH + secSlotH + gap + rH <= availH + 0.5) {
              bestFont = fs;
              break;
            }
          }

          final bestRfs = (bestFont * 0.55).clamp(13.0, refScaleMax);
          final bestGap = math.max(4.0, math.min(bestFont * 0.28, 22.0));

          // Re-measure at chosen font to compute centering offset.
          final finalBodyH = body.isNotEmpty
              ? (_makePainterForFit(body, bestFont, bodyLineH)
                    ..layout(maxWidth: availW))
                  .height
              : 0.0;
          final finalRefH = (_makePainterForFit(
                item.reference,
                bestRfs,
                refLineH,
                maxLines: 1,
              )..layout(maxWidth: availW))
              .height;

          // Reserve space for secondary + gap + reference so the body SizedBox
          // never pushes the Column beyond availH (prevents overflow stripe).
          final fixedFooterH = secGapH + secSlotH + bestGap + finalRefH;
          final bodyAlloc = math.max(0.0, availH - fixedFooterH);
          final clampedBodyH = finalBodyH.clamp(0.0, bodyAlloc);
          final clampedBlockH = clampedBodyH + fixedFooterH;
          final topPad = math.max(0.0, (availH - clampedBlockH) / 2.0);

          // Justify only for long passages with many lines; prefer left
          // for typical short/medium verses to avoid ugly word gaps.
          final approxLines = bestFont * bodyLineH > 0 && clampedBodyH > 0
              ? (clampedBodyH / (bestFont * bodyLineH)).round()
              : 0;
          final bodyAlign = approxLines >= 5 && body.length >= 300
              ? TextAlign.justify
              : TextAlign.left;

          return Padding(
            padding: EdgeInsets.all(inset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(height: topPad),
                if (body.isNotEmpty)
                  SizedBox(
                    height: clampedBodyH,
                    child: Text(
                      body,
                      textAlign: bodyAlign,
                      softWrap: true,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: const Color(0xFFF2EFE8),
                        fontWeight: FontWeight.w400,
                        height: bodyLineH,
                        fontSize: bestFont,
                      ),
                    ),
                  ),
                if (hasSecondary) ...[
                  SizedBox(height: secGapH),
                  SizedBox(
                    height: secSlotH,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: TagPresentationAutoFitText(
                        text: secondaryText!.trim(),
                        style: const TextStyle(
                          color: Color(0xFFD7CBB4),
                          fontWeight: FontWeight.w400,
                          height: 1.16,
                          fontStyle: FontStyle.italic,
                        ),
                        minFontSize: 10,
                        maxFontSize: 16,
                        maxLines: 2,
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ),
                ],
                SizedBox(height: bestGap),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    item.reference,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFF0D68A),
                      fontWeight: FontWeight.w600,
                      height: refLineH,
                      fontSize: bestRfs,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Heading: reference at top-left, body below.
        final referenceSlotHeight = math.max(
          18.0,
          math.min(30.0, height * 0.09),
        );
        return Padding(
          padding: EdgeInsets.all(inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(
                height: referenceSlotHeight,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: TagPresentationAutoFitText(
                    text: item.reference,
                    style: const TextStyle(
                      color: Color(0xFFF0D68A),
                      fontWeight: FontWeight.w700,
                      height: 1.02,
                    ),
                    minFontSize: 12.0,
                    maxFontSize: 30.0,
                    maxLines: 1,
                    textAlign: TextAlign.left,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              if ((item.body ?? '').trim().isNotEmpty) ...[
                SizedBox(height: math.max(6.0, height * 0.015)),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: TagPresentationAutoFitText(
                      text: item.body!.trim(),
                      style: const TextStyle(
                        color: Color(0xFFF2EFE8),
                        fontWeight: FontWeight.w400,
                        height: 1.20,
                      ),
                      minFontSize: bodyMin,
                      maxFontSize: bodyMax,
                      maxLines: null,
                      textAlign: TextAlign.left,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              if ((secondaryText ?? '').trim().isNotEmpty) ...[
                SizedBox(height: math.max(4.0, height * 0.01)),
                SizedBox(
                  height: math.max(14.0, math.min(18.0, height * 0.08)),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: TagPresentationAutoFitText(
                      text: secondaryText!.trim(),
                      style: const TextStyle(
                        color: Color(0xFFD7CBB4),
                        fontWeight: FontWeight.w400,
                        height: 1.16,
                        fontStyle: FontStyle.italic,
                      ),
                      minFontSize: 10,
                      maxFontSize: 16,
                      maxLines: 2,
                      textAlign: TextAlign.left,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PreviewNotePanel extends StatelessWidget {
  const _PreviewNotePanel({required this.item});

  final _PreviewResolvedItem item;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final body = item.body?.trim() ?? '';
        final inset = math.max(4.0, width * 0.012);
        final availW = math.max(8.0, width - 2 * inset);
        final availH = math.max(8.0, height - 2 * inset);

        // Only show the reference label when it is a real citation/title, not
        // the generic fallback word "Note".
        final refLabel = item.reference.trim();
        final hasRef =
            refLabel.isNotEmpty && refLabel.toLowerCase() != 'note';

        const bodyLineH = 1.20;
        const refLineH = 1.02;
        // Allow font to shrink to 8 px for small cells before clipping.
        const minFont = 8.0;

        // Combined-block fitting: body + optional reference at bottom-right,
        // vertically centred.  Same approach as the scripture block so note
        // slides in merged / full-slide zones fill the space aggressively.
        final refScaleMax = math.max(22.0, math.min(availH * 0.15, 54.0));
        final maxFont = _noteBodyMaxFontSize(
          body,
          width: availW,
          height: availH,
        );

        var bestFont = minFont;
        if (body.isNotEmpty) {
          for (var fs = maxFont; fs >= minFont; fs -= 1.0) {
            final rfs = hasRef
                ? (fs * 0.55).clamp(13.0, refScaleMax)
                : 0.0;
            final gap = hasRef
                ? math.max(4.0, math.min(fs * 0.28, 20.0))
                : 0.0;
            final bH = (_makePainterForFit(body, fs, bodyLineH)
                  ..layout(maxWidth: availW))
                .height;
            final rH = hasRef
                ? (_makePainterForFit(refLabel, rfs, refLineH, maxLines: 1)
                      ..layout(maxWidth: availW))
                    .height
                : 0.0;
            if (bH + gap + rH <= availH + 0.5) {
              bestFont = fs;
              break;
            }
          }
        }

        final bestRfs = hasRef
            ? (bestFont * 0.55).clamp(13.0, refScaleMax)
            : 0.0;
        final bestGap = hasRef
            ? math.max(4.0, math.min(bestFont * 0.28, 20.0))
            : 0.0;

        final finalBodyH = body.isNotEmpty
            ? (_makePainterForFit(body, bestFont, bodyLineH)
                  ..layout(maxWidth: availW))
                .height
            : 0.0;
        final finalRefH = hasRef
            ? (_makePainterForFit(refLabel, bestRfs, refLineH, maxLines: 1)
                  ..layout(maxWidth: availW))
                .height
            : 0.0;

        // Cap body height so Column children never exceed availH.
        final bodyAlloc = math.max(
          0.0,
          availH - (hasRef ? bestGap + finalRefH : 0.0),
        );
        final clampedBodyH = finalBodyH.clamp(0.0, bodyAlloc);
        final clampedBlockH =
            clampedBodyH + (hasRef ? bestGap + finalRefH : 0.0);
        final topPad = math.max(0.0, (availH - clampedBlockH) / 2.0);

        final approxLines = bestFont * bodyLineH > 0 && clampedBodyH > 0
            ? (clampedBodyH / (bestFont * bodyLineH)).round()
            : 0;
        final bodyAlign = body.length >= 300 && approxLines >= 5
            ? TextAlign.justify
            : TextAlign.left;

        return Padding(
          padding: EdgeInsets.all(inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(height: topPad),
              if (body.isNotEmpty)
                SizedBox(
                  height: clampedBodyH,
                  child: Text(
                    body,
                    textAlign: bodyAlign,
                    softWrap: true,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      color: const Color(0xFFF2EFE8),
                      fontWeight: FontWeight.w400,
                      height: bodyLineH,
                      fontSize: bestFont,
                    ),
                  ),
                ),
              if (hasRef) ...[
                SizedBox(height: bestGap),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    refLabel,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFF0D68A),
                      fontWeight: FontWeight.w600,
                      height: refLineH,
                      fontSize: bestRfs,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PreviewMediaPanel extends StatelessWidget {
  const _PreviewMediaPanel({required this.item, this.mediaRoots});

  final _PreviewResolvedItem item;
  final List<String>? mediaRoots;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final caption = _presentationFriendlyText(item.caption);
        final inset = math.max(4.0, width * 0.012);
        final mediaPath =
            TagPresentationMediaPathResolver.resolveStoredMediaPath(
              item.mediaPath,
              mediaRoots ?? const <String>[],
            );
        final resolved = mediaPath != null && File(mediaPath).existsSync();
        return Padding(
          padding: EdgeInsets.all(inset),
          child: resolved
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    SizedBox.expand(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(mediaPath),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                    if ((caption ?? '').trim().isNotEmpty &&
                        width >= 180 &&
                        height >= 160)
                      Positioned(
                        left: math.max(8.0, width * 0.02),
                        right: math.max(8.0, width * 0.02),
                        bottom: math.max(8.0, height * 0.02),
                        child: _PresentationCaptionChip(text: caption!.trim()),
                      ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        Icons.image_outlined,
                        color: const Color(0xFFF0D68A).withValues(alpha: 0.9),
                        size: math.min(width, height) * 0.12,
                      ),
                    ),
                    SizedBox(height: math.max(10.0, height * 0.02)),
                    Text(
                      'Image unavailable for presentation',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFFF2EFE8).withValues(alpha: 0.96),
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                    if ((caption ?? '').trim().isNotEmpty &&
                        width >= 180 &&
                        height >= 160) ...[
                      SizedBox(height: math.max(6.0, height * 0.01)),
                      Text(
                        caption!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFD7CBB4).withValues(alpha: 0.9),
                          fontWeight: FontWeight.w400,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

double _previewBodyMaxFontSize(
  String? body, {
  double width = 0.0,
  double height = 0.0,
}) {
  final length = (body ?? '').trim().length;
  // Length-based ceiling: shorter text can render larger.
  final lengthBased = switch (length) {
    <= 40 => 48.0,
    <= 100 => 40.0,
    <= 200 => 34.0,
    <= 350 => 28.0,
    <= 500 => 24.0,
    _ => 20.0,
  };
  // Zone-based ceiling: merged/larger zones allow the font to grow further.
  // TagPresentationAutoFitText steps down from this cap until the text fits,
  // so setting it high is safe — it only governs the search upper bound.
  final zoneBased = math.min(
    48.0,
    math.max(16.0, math.min(width / 10.0, height / 3.0)),
  );
  return math.min(lengthBased, zoneBased);
}

/// Creates a [TextPainter] configured for combined-block scripture fitting.
/// Call `..layout(maxWidth: w)` on the result before reading dimensions.
TextPainter _makePainterForFit(
  String text,
  double fontSize,
  double lineHeight, {
  int? maxLines,
  FontWeight fontWeight = FontWeight.w400,
}) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        height: lineHeight,
        fontWeight: fontWeight,
      ),
    ),
    textAlign: TextAlign.left,
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: maxLines != null ? '…' : null,
  );
}

/// Upper-bound font size for the scripture / eLibrary combined-block fitter.
/// The fitter iterates from this ceiling downward, taking the largest font
/// whose combined body + reference block fits within the zone height
/// (target vertical fill 55–85 %).
///
/// The ceiling is zone-aware: merged / full-slide zones are allowed to start
/// the search much higher so medium-length passages are not artificially
/// capped at a small size.  The zone-based formula `height / 2.0` keeps
/// the starting point proportional to the zone while the `zoneBoost` factor
/// scales the length-based ceiling upward for larger zones.
double _scriptureBodyMaxFontSize(
  String? body, {
  required double width,
  required double height,
}) {
  final length = (body ?? '').trim().length;
  // Zone boost: merged / full-slide zones (height > 140) raise the length-based
  // starting point so the fitter can explore larger fonts.
  final zoneBoost = (height / 140.0).clamp(1.0, 1.8);
  // Length-based ceiling — zone-boosted for medium/long text so that the same
  // verse in a 4-cell merged zone can grow well past the single-cell cap.
  final lengthBased = switch (length) {
    <= 50 => 96.0,
    <= 100 => 88.0,
    <= 200 => 76.0,
    <= 350 => (58.0 * zoneBoost).clamp(58.0, 88.0),
    <= 600 => (42.0 * zoneBoost).clamp(42.0, 68.0),
    _ => 30.0,
  };
  // Zone-based ceiling: proportional to zone size; width / 3.5 and height / 2.0
  // let the search start high for wide / tall zones.
  final zoneBased = math.min(
    96.0,
    math.max(18.0, math.min(width / 3.5, height / 2.0)),
  );
  return math.min(lengthBased, zoneBased);
}

/// Upper-bound font size for the note body fitter.
/// Zone-aware: larger zones allow the search to start higher so note text
/// fills merged / full-slide zones more aggressively.
double _noteBodyMaxFontSize(
  String? body, {
  required double width,
  required double height,
}) {
  final length = (body ?? '').trim().length;
  final zoneBoost = (height / 140.0).clamp(1.0, 1.8);
  final lengthBased = switch (length) {
    <= 50 => 96.0,
    <= 100 => 80.0,
    <= 200 => 68.0,
    <= 350 => (52.0 * zoneBoost).clamp(52.0, 82.0),
    <= 600 => (38.0 * zoneBoost).clamp(38.0, 62.0),
    _ => 26.0,
  };
  final zoneBased = math.min(
    96.0,
    math.max(18.0, math.min(width / 3.5, height / 2.0)),
  );
  return math.min(lengthBased, zoneBased);
}

enum _PreviewTextStyle { scripture, heading }

String _stripHtml(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _PresentationCaptionChip extends StatelessWidget {
  const _PresentationCaptionChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final caption = text.trim();
    if (caption.isEmpty) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF2E2619).withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFFF4EAD9).withValues(alpha: 0.98),
            fontWeight: FontWeight.w500,
            fontSize: 12,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
