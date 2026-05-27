import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/bootstrap/library_root_service.dart';
import '../../../../core/database/study_bible_database.dart';
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
    final title = _cleanText(elibrary.sourceTitle);
    if (title != null) return title;
    final location = _cleanText(elibrary.sourceLocation);
    if (location != null) return location;
    return elibrary.compactRef;
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
  final title = _cleanText(elibrary.sourceTitle);
  if (title != null) return title;
  final location = _cleanText(elibrary.sourceLocation);
  if (location != null) return location;
  final referenceText = _cleanText(elibrary.sourceReferenceText);
  if (referenceText != null) return referenceText;
  return elibrary.compactRef;
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
  final media = item.media.first;
  final caption = _presentationLabelOrNull(media.caption);
  if (caption != null) return caption;
  final path = _presentationLabelOrNull(media.relativePath);
  if (path != null) {
    final segments = path.split('/');
    return segments.isEmpty ? path : segments.last;
  }
  return null;
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
  if (lower.startsWith('note:')) return true;
  if (lower.startsWith('content_')) return true;
  if (lower.startsWith('media_')) return true;
  if (lower.startsWith('file_')) return true;
  if (lower.startsWith('img_')) return true;
  if (lower.startsWith('hash:')) return true;
  if (lower.contains('tag_item_media')) return true;
  if (lower.contains('contentid') || lower.contains('noteid')) return true;
  if (lower.contains('selectedtextsnapshot')) return true;
  if (lower.contains('sourceparagraph')) return true;
  if (lower.contains('relativepath')) return true;
  if (lower.contains('/') && text.length > 18) return true;
  if (RegExp(r'^[a-f0-9]{12,}$', caseSensitive: false).hasMatch(text)) {
    return true;
  }
  if (RegExp(
    r'^(note|content|media)[:_-]?\d+',
    caseSensitive: false,
  ).hasMatch(text)) {
    return true;
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
        final referenceMax = 30.0;
        final referenceMin = 12.0;
        final bodyMax = _previewBodyMaxFontSize(
          item.body,
          width: width,
          height: height,
        );
        final bodyMin = isHeading ? 12.0 : 14.0;
        final referenceSlotHeight = math.max(
          18.0,
          math.min(30.0, height * 0.09),
        );
        final secondaryText = _presentationFriendlyText(item.secondary);

        final inset = math.max(4.0, width * 0.012);
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
                    minFontSize: referenceMin,
                    maxFontSize: referenceMax,
                    maxLines: 1,
                    textAlign: TextAlign.left,
                    letterSpacing: isHeading ? 0.1 : 0.0,
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
                      maxFontSize: math.min(26.0, bodyMax),
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
        return Padding(
          padding: EdgeInsets.all(inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(
                height: math.max(16.0, math.min(22.0, height * 0.09)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: TagPresentationAutoFitText(
                    text: item.reference,
                    style: const TextStyle(
                      color: Color(0xFFF0D68A),
                      fontWeight: FontWeight.w700,
                      height: 1.04,
                    ),
                    minFontSize: 12,
                    maxFontSize: 30,
                    maxLines: 1,
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
              if (body.isNotEmpty) ...[
                SizedBox(height: math.max(4.0, height * 0.01)),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: TagPresentationAutoFitText(
                      text: body,
                      style: const TextStyle(
                        color: Color(0xFFF2EFE8),
                        fontWeight: FontWeight.w400,
                        height: 1.18,
                      ),
                      minFontSize: 14,
                      maxFontSize: math.min(
                        26.0,
                        _previewBodyMaxFontSize(
                          body,
                          width: width,
                          height: height,
                        ),
                      ),
                      maxLines: null,
                      textAlign: TextAlign.left,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
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
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(mediaPath),
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
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
  final lengthBased = switch (length) {
    <= 60 => 26.0,
    <= 140 => 24.0,
    <= 260 => 22.0,
    <= 420 => 20.0,
    _ => 18.0,
  };
  final zoneBased = math.min(
    26.0,
    math.max(16.0, math.min(width / 20.0, height / 5.0)),
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
