import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/presentation/presentation_models.dart';
import '../data/presentation/note_image_layout.dart';
import 'note_image_flow.dart';
import 'presentation_fit.dart';
import 'presentation_element.dart';
import '../data/presentation/presentation_slide_settings.dart';
import '../data/presentation/presentation_text_format.dart';
import 'viewer_presentation_settings.dart';
import 'presentation_prep/tag_presentation_media_path_resolver.dart';

class PresentationSlideCanvas extends StatefulWidget {
  const PresentationSlideCanvas({
    super.key,
    required this.slide,
    required this.aspectRatioPreset,
    required this.bookNames,
    required this.settings,
    required this.mediaRootPaths,
    this.onBodyFontSizeResolved,
  });

  final PresentationSlide slide;
  final PresentationAspectRatioPreset aspectRatioPreset;
  final Map<int, String> bookNames;
  final PresentationSlideSettings settings;
  final List<String> mediaRootPaths;
  final ValueChanged<double>? onBodyFontSizeResolved;

  @override
  State<PresentationSlideCanvas> createState() =>
      _PresentationSlideCanvasState();
}

class _PresentationSlideCanvasState extends State<PresentationSlideCanvas> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _leftScrollController = ScrollController();
  final ScrollController _rightScrollController = ScrollController();
  final Map<String, Future<_MediaDimensions?>> _mediaDimensionsCache =
      <String, Future<_MediaDimensions?>>{};

  @override
  void dispose() {
    _scrollController.dispose();
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }

  PresentationSlide get _slide => widget.slide;

  PresentationBlockAlignments _alignments(PresentationSlide slide) =>
      PresentationBlockAlignments.fromFormat(
        slide.items.firstOrNull?.noteFormatJson,
      );

  String _slideTitle(PresentationSlide slide) {
    return slide.slideTitle?.trim() ?? '';
  }

  String _bookNameFor(int bookNumber) {
    return widget.bookNames[bookNumber] ?? 'Book $bookNumber';
  }

  String _referenceHeadingForItem(PresentationSlideItem item) {
    if (item.bookNumber <= 0 || item.chapter <= 0 || item.verse <= 0) {
      return '';
    }
    final verseLabel = item.verseEnd > item.verse
        ? '${item.verse}-${item.verseEnd}'
        : '${item.verse}';
    return '${_bookNameFor(item.bookNumber)} ${item.chapter}:$verseLabel';
  }

  bool _hasVerseItems(PresentationSlide slide) {
    return slide.items.any(
      (item) => item.itemKind == PresentationItemKind.verse,
    );
  }

  bool _hasNoteItems(PresentationSlide slide) {
    return slide.items.any(
      (item) => item.itemKind == PresentationItemKind.note,
    );
  }

  bool _hasMediaItems(PresentationSlide slide) {
    return slide.items.any((item) => item.mediaRefs?.isNotEmpty == true);
  }

  PresentationLayoutPreference _layoutPreferenceForSlide(
    PresentationSlide slide,
  ) {
    return widget.settings.layoutOverride ?? PresentationLayoutPreference.auto;
  }

  bool _hasTextContent(PresentationSlideItem item) {
    final verseText = item.displayText.trim();
    final noteText = item.noteText?.trim() ?? '';
    return verseText.isNotEmpty || noteText.isNotEmpty;
  }

  bool _hasMediaContent(PresentationSlideItem item) {
    return item.mediaRefs?.isNotEmpty == true;
  }

  bool _slideHasText(PresentationSlide slide) {
    return slide.items.any(_hasTextContent);
  }

  bool _slideHasMedia(PresentationSlide slide) {
    return _hasMediaItems(slide);
  }

  NoteImageLayout? _itemImageLayout(PresentationSlideItem item) {
    final layout = resolveNoteImageLayout(
      noteImageLayoutFromFormat(item.noteFormatJson),
      widget.settings.imageLayouts[presentationElementKey(item.id, 'image')],
    );
    if (layout == null || layout.imageIndex >= (item.mediaRefs?.length ?? 0))
      return null;
    if (item.itemKind == PresentationItemKind.verse &&
        layout.footer.trim().isEmpty) {
      return NoteImageLayout.fromJson({
        ...layout.toJson(),
        'footer': item.citationText?.trim().isNotEmpty == true
            ? item.citationText!.trim()
            : _referenceHeadingForItem(item),
      });
    }
    return layout;
  }

  NoteImageLayout? _noteImageLayout(PresentationSlide slide) =>
      slide.items.length == 1 ? _itemImageLayout(slide.items.single) : null;

  bool _hasImageZones(PresentationSlide slide) =>
      slide.items.any((item) => _itemImageLayout(item) != null);

  PresentationLayoutPreference _effectiveLayoutPreference(
    PresentationSlide slide,
  ) {
    if (_hasImageZones(slide)) return PresentationLayoutPreference.textOnly;
    final override = _layoutPreferenceForSlide(slide);
    if (override != PresentationLayoutPreference.auto) return override;
    final hasText = _slideHasText(slide);
    final hasMedia = _slideHasMedia(slide);
    if (hasText && hasMedia) {
      return PresentationLayoutPreference.textLeftImageRight;
    }
    if (hasMedia) {
      return PresentationLayoutPreference.imageOnly;
    }
    return PresentationLayoutPreference.textOnly;
  }

  bool _isHorizontalSplitLayout(PresentationLayoutPreference value) {
    return switch (value) {
      PresentationLayoutPreference.textLeftImageRight => true,
      PresentationLayoutPreference.imageLeftTextRight => true,
      PresentationLayoutPreference.textLeftTwoThirdsImageRightOneThird => true,
      PresentationLayoutPreference.textLeftThreeQuarterImageRightOneQuarter =>
        true,
      _ => false,
    };
  }

  bool _isVerticalSplitLayout(PresentationLayoutPreference value) {
    return switch (value) {
      PresentationLayoutPreference.textTopImageBottom => true,
      PresentationLayoutPreference.imageTopTextBottom => true,
      _ => false,
    };
  }

  bool _isOverlayLayout(PresentationLayoutPreference value) {
    return value == PresentationLayoutPreference.imageBackgroundTextOverlay;
  }

  bool _isImageOnlyLayout(PresentationLayoutPreference value) {
    return value == PresentationLayoutPreference.imageOnly;
  }

  List<PresentationSlideItem> _verseItems(PresentationSlide slide) {
    return slide.items
        .where((item) => item.itemKind == PresentationItemKind.verse)
        .toList(growable: false);
  }

  List<PresentationSlideItem> _noteItems(PresentationSlide slide) {
    return slide.items
        .where((item) => item.itemKind == PresentationItemKind.note)
        .toList(growable: false);
  }

  String _twoColumnLeftMeasurementText(PresentationSlide slide) {
    final blocks = <String>[];
    for (final item in _verseItems(slide)) {
      final text = item.displayText.trim();
      final citationText = item.citationText?.trim().isNotEmpty == true
          ? item.citationText!.trim()
          : _referenceHeadingForItem(item);
      final noteText = item.noteText?.trim() ?? '';
      if (text.isEmpty && citationText.isEmpty && noteText.isEmpty) continue;
      final parts = <String>[
        if (text.isNotEmpty) text,
        if (citationText.isNotEmpty) citationText,
        if (noteText.isNotEmpty && noteText != text) noteText,
      ];
      blocks.add(parts.join('\n'));
    }
    return blocks.join('\n\n');
  }

  String _twoColumnRightMeasurementText(PresentationSlide slide) {
    final blocks = <String>[];
    for (final item in _noteItems(slide)) {
      final text = item.displayText.trim();
      if (text.isNotEmpty) blocks.add(text);
    }
    return blocks.join('\n\n');
  }

  String? _resolveMediaPath(String relativePath) {
    return TagPresentationMediaPathResolver.resolveStoredMediaPath(
      relativePath,
      widget.mediaRootPaths,
    );
  }

  Future<_MediaDimensions?> _loadMediaDimensions(String relativePath) async {
    final resolved = _resolveMediaPath(relativePath);
    if (resolved == null) return null;
    final file = File(resolved);
    if (!await file.exists()) return null;

    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      return _MediaDimensions(
        width: frameInfo.image.width.toDouble(),
        height: frameInfo.image.height.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<_MediaDimensions?> _mediaDimensionsFor(String relativePath) {
    return _mediaDimensionsCache.putIfAbsent(
      relativePath,
      () => _loadMediaDimensions(relativePath),
    );
  }

  Widget _buildMediaPreview(
    String relativePath, {
    double maxWidth = 520,
    double maxHeight = 320,
    bool hasText = false,
  }) {
    final resolved = _resolveMediaPath(relativePath);
    if (resolved == null) {
      return _mediaUnavailablePreview(relativePath);
    }

    final file = File(resolved);
    if (!file.existsSync()) {
      return _mediaUnavailablePreview(relativePath);
    }

    return FutureBuilder<_MediaDimensions?>(
      future: _mediaDimensionsFor(relativePath),
      builder: (context, snapshot) {
        final dimensions = snapshot.data;
        final isPortrait = dimensions != null && dimensions.aspectRatio < 0.82;
        final isLandscape =
            dimensions == null || dimensions.aspectRatio >= 1.12;
        final aspectRatio = dimensions?.aspectRatio ?? 1.6;
        final preferredWidth = isPortrait
            ? math.min(maxWidth * 0.82, 480.0)
            : isLandscape
            ? maxWidth
            : math.min(maxWidth * 0.92, 720.0);
        final preferredHeight = isPortrait
            ? math.min(
                hasText ? maxHeight * 0.82 : maxHeight * 0.92,
                hasText ? 580.0 : 780.0,
              )
            : math.min(
                hasText ? maxHeight * 0.94 : maxHeight,
                hasText ? 760.0 : 860.0,
              );
        var imageWidth = preferredWidth;
        var imageHeight = imageWidth / aspectRatio;
        if (imageHeight > preferredHeight) {
          imageHeight = preferredHeight;
          imageWidth = imageHeight * aspectRatio;
        }
        imageWidth = math.min(maxWidth, math.max(120.0, imageWidth));
        imageHeight = math.min(maxHeight, math.max(80.0, imageHeight));

        return Align(
          alignment: isPortrait ? Alignment.topCenter : Alignment.center,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: imageWidth,
              height: imageHeight,
              color: const Color(0xFF0F1217),
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: isPortrait ? Alignment.topCenter : Alignment.center,
                child: Image.file(
                  file,
                  errorBuilder: (context, error, stackTrace) {
                    return _mediaUnavailablePreview(relativePath);
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _mediaUnavailablePreview(String relativePath) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          220.0,
          constraints.maxWidth.isFinite ? constraints.maxWidth : 220.0,
        );
        final height = math.min(
          140.0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 140.0,
        );
        final shortName = p.basename(relativePath).trim();

        return SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0F1217),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFE0BE87).withValues(alpha: 0.18),
              ),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        shortName.isEmpty ? 'Image unavailable' : shortName,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (shortName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'Image unavailable',
                          style: TextStyle(color: Colors.white54, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _presentationNoteSection({
    required String noteText,
    required TextStyle textStyle,
    required TextAlign textAlign,
    String? noteFormatJson,
    List<String> mediaRefs = const <String>[],
  }) {
    final hasText = noteText.trim().isNotEmpty;
    final hasMedia = mediaRefs.isNotEmpty;
    if (!hasText && !hasMedia) {
      return const SizedBox.shrink();
    }

    final centerContent = textAlign == TextAlign.center;
    final effectiveCenter = centerContent || (hasMedia && !hasText);
    final spanStyle = textStyle;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxPreviewWidth = effectiveCenter ? constraints.maxWidth : 520.0;
        final maxPreviewHeight = effectiveCenter
            ? math.min(
                hasText ? 620.0 : 760.0,
                constraints.maxHeight.isFinite
                    ? math.max(
                        hasText ? 320.0 : 360.0,
                        constraints.maxHeight * 0.95,
                      )
                    : (hasText ? 620.0 : 760.0),
              )
            : 320.0;
        final contentPadding = effectiveCenter
            ? const EdgeInsets.fromLTRB(10, 10, 10, 10)
            : const EdgeInsets.fromLTRB(14, 12, 14, 12);

        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1E24).withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFE0BE87).withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Padding(
            padding: contentPadding,
            child: Column(
              crossAxisAlignment: effectiveCenter
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.stretch,
              children: [
                if (hasMedia) ...[
                  Wrap(
                    alignment: effectiveCenter
                        ? WrapAlignment.center
                        : WrapAlignment.start,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final mediaRef in mediaRefs)
                        _buildMediaPreview(
                          mediaRef,
                          maxWidth: maxPreviewWidth,
                          maxHeight: maxPreviewHeight,
                          hasText: hasText,
                        ),
                    ],
                  ),
                ],
                if (hasText && hasMedia) const SizedBox(height: 10),
                if (hasText)
                  RichText(
                    textAlign: textAlign,
                    text: TextSpan(
                      children: buildPresentationTextSpans(
                        text: noteText,
                        baseStyle: spanStyle,
                        formatJson: noteFormatJson,
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

  Widget _headingViewport(
    String text,
    TextStyle style,
    double width,
    double height,
    Widget child,
  ) {
    final limit = math.max(60.0, height * .35);
    final measured = _measureTextHeight(
      text: text,
      style: style,
      maxWidth: math.max(1, width),
      textDirection: Directionality.of(context),
    );
    if (measured <= limit) return child;
    return SizedBox(
      height: limit,
      child: PresentationOverflowFrame(
        overflow: true,
        area: 'the heading',
        child: SingleChildScrollView(child: child),
      ),
    );
  }

  double _elementSize(String key, double fallback) =>
      widget.settings.fontSizeFor(key, fallback);

  Widget _element(
    PresentationSlideItem item,
    String part,
    double base,
    Widget child,
  ) {
    final number =
        _slide.items.indexWhere((candidate) => candidate.id == item.id) + 1;
    final label = switch (part) {
      'citation' => 'Reference $number',
      'note' => 'Note $number',
      _ =>
        item.itemKind == PresentationItemKind.note
            ? 'Note $number'
            : 'Passage $number',
    };
    return PresentationElement(
      elementKey: presentationElementKey(item.id, part),
      label: label,
      defaultFontSize: base,
      child: child,
    );
  }

  Widget _slideItemWidget({
    required PresentationSlideItem item,
    required String slideTitle,
    required TextStyle bodyStyle,
    required TextStyle noteTextStyle,
    required TextStyle headingStyle,
    required double bodyFontSize,
    required TextAlign bodyTextAlign,
    bool includeAttachedNote = true,
    TextAlign? attachedNoteAlign,
    bool includeMedia = false,
  }) {
    final bodyKey = presentationElementKey(item.id, 'body');
    if (item.itemKind == PresentationItemKind.note) {
      final base = item.mediaRefs?.isNotEmpty == true
          ? math.min(bodyFontSize, 30.0)
          : bodyFontSize;
      return _element(
        item,
        'body',
        base,
        _presentationNoteSection(
          noteText: item.displayText,
          textStyle: noteTextStyle.copyWith(
            fontSize: _elementSize(bodyKey, base),
          ),
          noteFormatJson: item.noteFormatJson,
          mediaRefs: item.mediaRefs ?? const <String>[],
          textAlign: widget.settings.alignmentFor(bodyKey, bodyTextAlign),
        ),
      );
    }
    final verseText = item.displayText.trim();
    final noteText = item.noteText?.trim() ?? '';
    final citationText = item.citationText?.trim().isNotEmpty == true
        ? item.citationText!.trim()
        : _referenceHeadingForItem(item);
    String normalized(String text) =>
        text.trim().replaceAll('–', '-').replaceAll('—', '-');
    final showCitation =
        citationText.isNotEmpty &&
        normalized(citationText) != normalized(slideTitle);
    final noteBase = math.min(bodyFontSize, 24.0);
    final citationBase = math.max(13.0, bodyFontSize * .36);
    final bodySize = _elementSize(bodyKey, bodyFontSize);
    final showNote =
        includeAttachedNote && noteText.isNotEmpty && noteText != verseText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (verseText.isNotEmpty)
          _element(
            item,
            'body',
            bodyFontSize,
            item.displayTextFormatJson?.trim().isNotEmpty == true
                ? RichText(
                    textAlign: widget.settings.alignmentFor(
                      bodyKey,
                      bodyTextAlign,
                    ),
                    text: TextSpan(
                      children: buildPresentationTextSpans(
                        text: verseText,
                        baseStyle: bodyStyle.copyWith(fontSize: bodySize),
                        formatJson: item.displayTextFormatJson,
                      ),
                    ),
                  )
                : Text(
                    verseText,
                    style: bodyStyle.copyWith(fontSize: bodySize),
                    textAlign: widget.settings.alignmentFor(
                      bodyKey,
                      bodyTextAlign,
                    ),
                    softWrap: true,
                  ),
          ),
        if (showCitation) ...[
          const SizedBox(height: 8),
          _element(
            item,
            'citation',
            citationBase,
            Text(
              citationText,
              textAlign: widget.settings.alignmentFor(
                presentationElementKey(item.id, 'citation'),
                PresentationBlockAlignments.fromFormat(
                  item.noteFormatJson,
                ).citation,
              ),
              style: headingStyle.copyWith(
                fontSize: _elementSize(
                  presentationElementKey(item.id, 'citation'),
                  citationBase,
                ),
              ),
              softWrap: true,
            ),
          ),
        ],
        if (showNote) ...[
          const SizedBox(height: 12),
          _element(
            item,
            'note',
            noteBase,
            _presentationNoteSection(
              noteText: noteText,
              textStyle: noteTextStyle.copyWith(
                fontSize: _elementSize(
                  presentationElementKey(item.id, 'note'),
                  noteBase,
                ),
              ),
              noteFormatJson: item.noteFormatJson,
              mediaRefs: item.mediaRefs ?? const <String>[],
              textAlign: widget.settings.alignmentFor(
                presentationElementKey(item.id, 'note'),
                attachedNoteAlign ?? bodyTextAlign,
              ),
            ),
          ),
        ],
        if (includeMedia &&
            item.mediaRefs?.isNotEmpty == true &&
            !showNote) ...[
          const SizedBox(height: 12),
          _presentationNoteSection(
            noteText: '',
            textStyle: noteTextStyle.copyWith(fontSize: noteBase),
            noteFormatJson: null,
            mediaRefs: item.mediaRefs ?? const <String>[],
            textAlign: attachedNoteAlign ?? bodyTextAlign,
          ),
        ],
      ],
    );
  }

  Widget _zoneItemWidget({
    required PresentationSlideItem item,
    required bool renderText,
    required bool renderMedia,
    required String slideTitle,
    required TextStyle bodyStyle,
    required TextStyle noteTextStyle,
    required TextStyle headingStyle,
    required double bodyFontSize,
    required TextAlign bodyTextAlign,
  }) {
    if (item.itemKind == PresentationItemKind.note) {
      final noteText = item.noteText?.trim().isNotEmpty == true
          ? item.noteText!.trim()
          : item.displayText.trim();
      if (!renderText && renderMedia && item.mediaRefs?.isNotEmpty == true) {
        return _presentationNoteSection(
          noteText: '',
          textStyle: noteTextStyle.copyWith(fontSize: bodyFontSize),
          noteFormatJson: null,
          mediaRefs: item.mediaRefs ?? const <String>[],
          textAlign: widget.settings.alignmentFor(
            presentationElementKey(item.id, 'body'),
            bodyTextAlign,
          ),
        );
      }
      return _element(
        item,
        'body',
        bodyFontSize,
        _presentationNoteSection(
          noteText: noteText,
          textStyle: noteTextStyle.copyWith(
            fontSize: _elementSize(
              presentationElementKey(item.id, 'body'),
              bodyFontSize,
            ),
          ),
          noteFormatJson: item.noteFormatJson,
          mediaRefs: renderMedia
              ? item.mediaRefs ?? const <String>[]
              : const <String>[],
          textAlign: widget.settings.alignmentFor(
            presentationElementKey(item.id, 'body'),
            bodyTextAlign,
          ),
        ),
      );
    }

    if (!renderText && renderMedia && item.mediaRefs?.isNotEmpty == true) {
      return _presentationNoteSection(
        noteText: '',
        textStyle: noteTextStyle.copyWith(fontSize: bodyFontSize),
        noteFormatJson: null,
        mediaRefs: item.mediaRefs ?? const <String>[],
        textAlign: widget.settings.alignmentFor(
          presentationElementKey(item.id, 'body'),
          bodyTextAlign,
        ),
      );
    }

    return _slideItemWidget(
      item: item,
      slideTitle: slideTitle,
      bodyStyle: bodyStyle,
      noteTextStyle: noteTextStyle,
      headingStyle: headingStyle,
      bodyFontSize: bodyFontSize,
      bodyTextAlign: bodyTextAlign,
      includeMedia: renderMedia,
    );
  }

  double _fitFontSize({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double maxHeight,
    required double minFontSize,
    required double maxFontSize,
    required TextDirection textDirection,
    TextAlign textAlign = TextAlign.left,
    double safetyBuffer = 12.0,
  }) {
    var low = minFontSize;
    var high = math.max(minFontSize, maxFontSize);
    var best = minFontSize;

    bool fits(double size) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(fontSize: size),
        ),
        textDirection: textDirection,
        textAlign: textAlign,
        textWidthBasis: TextWidthBasis.parent,
        maxLines: null,
      )..layout(maxWidth: maxWidth);
      return !painter.didExceedMaxLines &&
          painter.height <= math.max(0.0, maxHeight - safetyBuffer);
    }

    if (!fits(minFontSize)) return minFontSize;

    while ((high - low) > 0.25) {
      final mid = (low + high) / 2;
      if (fits(mid)) {
        best = mid;
        low = mid;
      } else {
        high = mid;
      }
    }
    return best;
  }

  double _measureTextHeight({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required TextDirection textDirection,
    TextAlign textAlign = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textAlign: textAlign,
      textWidthBasis: TextWidthBasis.parent,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  PresentationAlignmentPreference _defaultBodyAlignment(
    PresentationSlide slide,
  ) {
    return widget.settings.alignmentOverride ??
        PresentationAlignmentPreference.left;
  }

  TextAlign _bodyTextAlign(PresentationSlide slide) {
    if (widget.settings.alignmentOverride == null)
      return _alignments(slide).body;
    final alignment = _defaultBodyAlignment(slide);
    return switch (alignment) {
      PresentationAlignmentPreference.left => TextAlign.left,
      PresentationAlignmentPreference.center => TextAlign.center,
      PresentationAlignmentPreference.right => TextAlign.right,
      PresentationAlignmentPreference.justify => TextAlign.justify,
    };
  }

  double _chosenBodyFontSize({
    required PresentationSlide slide,
    required TextStyle bodyStyle,
    required TextStyle noteTextStyle,
    required double bodyMinFontSize,
    required double bodyMaxFontSize,
    required double bodyWidth,
    required double bodyHeight,
    required TextDirection textDirection,
    required TextAlign bodyTextAlign,
  }) {
    double resolved(double size) {
      widget.onBodyFontSizeResolved?.call(size);
      return size;
    }

    final override = widget.settings.fontSizeOverride;
    if (override != null) return resolved(override);
    if (!widget.settings.autoFitEnabled) return resolved(bodyMinFontSize);

    double height(double size) => _renderedTextHeight(
      slide,
      bodyWidth,
      size,
      bodyStyle,
      noteTextStyle,
      _fitHeadingStyle,
      bodyTextAlign,
    );
    var low = bodyMinFontSize;
    var high = math.max(low, bodyMaxFontSize);
    if (height(low) > bodyHeight) return resolved(low);
    while (high - low > .25) {
      final mid = (low + high) / 2;
      if (height(mid) <= bodyHeight - 2) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return resolved(low);
  }

  TextStyle get _fitHeadingStyle =>
      (Theme.of(context).textTheme.titleSmall ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w800,
        height: 1.12,
        letterSpacing: .08,
      );

  double _renderedTextHeight(
    PresentationSlide slide,
    double width,
    double size,
    TextStyle body,
    TextStyle note,
    TextStyle heading,
    TextAlign alignment,
  ) => presentationTextHeight(
    settings: widget.settings,
    slide: slide,
    bookNames: widget.bookNames,
    width: width,
    fontSize: size,
    bodyStyle: body,
    noteStyle: note,
    headingStyle: heading,
    direction: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    alignment: alignment,
  );

  Widget _buildFullWidthSlideBody({
    required BuildContext context,
    required PresentationSlide slide,
    required TextStyle bodyStyle,
    required TextStyle noteTextStyle,
    required TextStyle headingStyle,
    required double bodyMinFontSize,
    required double bodyMaxFontSize,
  }) {
    final bodyTextAlign = _bodyTextAlign(slide);
    if (slide.items.length > 1 && _hasImageZones(slide)) {
      // A linked slide still owns separate entry layouts. Do not discard those
      // reservations or substitute the list-wide two-column media layout.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in slide.items)
            Expanded(
              flex: math.max(
                120,
                item.displayText.length + (item.noteText?.length ?? 0),
              ),
              child: PresentationSlideCanvas(
                key: ValueKey('image-zone:${item.id}'),
                slide: PresentationSlide(
                  id: slide.id,
                  settingsKey: slide.settingsKey,
                  slideNumber: slide.slideNumber,
                  layoutType: PresentationLayoutType.fullWidth,
                  items: [item],
                ),
                aspectRatioPreset: PresentationAspectRatioPreset.auto,
                bookNames: widget.bookNames,
                settings: widget.settings,
                mediaRootPaths: widget.mediaRootPaths,
              ),
            ),
        ],
      );
    }
    return Padding(
      padding: _hasMediaItems(slide)
          ? const EdgeInsets.fromLTRB(10, 0, 10, 36)
          : EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, bodyConstraints) {
          final bodyWidth = math.max(0.0, bodyConstraints.maxWidth);
          final bodyHeight = math.max(0.0, bodyConstraints.maxHeight);
          final imageLayout = _noteImageLayout(slide);
          if (imageLayout != null) {
            final item = slide.items.single;
            final path = _resolveMediaPath(
              item.mediaRefs![imageLayout.imageIndex],
            );
            final isVerse = item.itemKind == PresentationItemKind.verse;
            final attachedNote = isVerse ? (item.noteText?.trim() ?? '') : '';
            final flow = NoteImageFlow(
              footerElementPart: isVerse ? 'citation' : 'footer',
              minimumDisplayedFontSize: 18,
              elementItemId: item.id,
              elementFontSizes: widget.settings.elementFontSizes,
              elementAlignments: widget.settings.elementAlignments,
              displayedFontSizeOverride: widget.settings.fontSizeOverride,
              onDisplayedFontSizeResolved: widget.onBodyFontSizeResolved,
              text: item.displayText,
              formatJson: isVerse
                  ? PresentationBlockAlignments.fromFormat(
                      item.noteFormatJson,
                    ).withFormat(item.displayTextFormatJson)
                  : item.noteFormatJson,
              layout: imageLayout,
              aspectRatio:
                  widget.aspectRatioPreset.aspectRatio ??
                  bodyWidth / math.max(1.0, bodyHeight),
              style: (isVerse ? bodyStyle : noteTextStyle).copyWith(
                fontSize: bodyMaxFontSize,
              ),
              image: path == null
                  ? const Icon(Icons.broken_image_outlined)
                  : Image.file(
                      File(path),
                      fit: imageLayout.fill ? BoxFit.cover : BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            );
            if (attachedNote.isEmpty || attachedNote == item.displayText.trim())
              return flow;
            final noteBase = math.min(
              widget.settings.fontSizeOverride ?? bodyMaxFontSize,
              24.0,
            );
            final noteKey = presentationElementKey(item.id, 'note');
            // The attached explanation remains independently editable and takes
            // real space away from the Scripture/image region before fitting.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: flow),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: bodyHeight * .4),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _element(
                        item,
                        'note',
                        noteBase,
                        _presentationNoteSection(
                          noteText: attachedNote,
                          textStyle: noteTextStyle.copyWith(
                            fontSize: _elementSize(noteKey, noteBase),
                          ),
                          noteFormatJson: item.noteFormatJson,
                          textAlign: widget.settings.alignmentFor(
                            noteKey,
                            bodyTextAlign,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          final chosenSlideBodySize = _chosenBodyFontSize(
            slide: slide,
            bodyStyle: bodyStyle,
            noteTextStyle: noteTextStyle,
            bodyMinFontSize: bodyMinFontSize,
            bodyMaxFontSize: bodyMaxFontSize,
            bodyWidth: bodyWidth,
            bodyHeight: bodyHeight,
            textDirection: Directionality.of(context),
            bodyTextAlign: bodyTextAlign,
          );
          final isNoteOnlySlide =
              _hasNoteItems(slide) && !_hasVerseItems(slide);
          if (isNoteOnlySlide && _hasMediaItems(slide)) {
            return _buildImageFocusedSlideBody(
              context: context,
              slide: slide,
              bodyWidth: bodyWidth,
              bodyHeight: bodyHeight,
            );
          }
          final needsInnerScroll =
              _renderedTextHeight(
                slide,
                bodyWidth,
                chosenSlideBodySize,
                bodyStyle,
                noteTextStyle,
                headingStyle,
                bodyTextAlign,
              ) >
              bodyHeight;

          return PresentationOverflowFrame(
            overflow: needsInnerScroll,
            child: SingleChildScrollView(
              controller: _scrollController,
              primary: false,
              physics: needsInnerScroll
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: bodyHeight),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < slide.items.length; i++) ...[
                        _slideItemWidget(
                          item: slide.items[i],
                          slideTitle: slide.slideTitle?.trim() ?? '',
                          bodyStyle: bodyStyle,
                          noteTextStyle: noteTextStyle,
                          headingStyle: headingStyle,
                          bodyFontSize: chosenSlideBodySize,
                          bodyTextAlign: bodyTextAlign,
                          attachedNoteAlign: bodyTextAlign,
                          includeMedia: true,
                        ),
                        if (i < slide.items.length - 1)
                          const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImageFocusedSlideBody({
    required BuildContext context,
    required PresentationSlide slide,
    required double bodyWidth,
    required double bodyHeight,
  }) {
    final mediaRefs = slide.items
        .where((item) => item.mediaRefs?.isNotEmpty == true)
        .expand((item) => item.mediaRefs!)
        .toList(growable: false);
    if (mediaRefs.isEmpty) {
      return const SizedBox.shrink();
    }

    final primaryMediaRef = mediaRefs.first;
    final captions = slide.items
        .where(
          (item) =>
              item.itemKind == PresentationItemKind.note &&
              item.displayText.trim().isNotEmpty,
        )
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(0.0, constraints.maxWidth);
        final availableHeight = math.max(0.0, constraints.maxHeight);
        final captionStyle =
            (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
                .copyWith(
                  color: const Color(0xFFEADCC2),
                  fontWeight: FontWeight.w400,
                  height: 1.18,
                  fontSize: 22,
                );
        const captionBase = 22.0;
        final captionHeight =
            captions.fold<double>(
              0,
              (height, item) =>
                  height +
                  _measureTextHeight(
                    text: item.displayText.trim(),
                    style: captionStyle.copyWith(
                      fontSize: _elementSize(
                        presentationElementKey(item.id, 'body'),
                        captionBase,
                      ),
                    ),
                    maxWidth: math.max(1.0, availableWidth * .9),
                    textDirection: Directionality.of(context),
                    textAlign: widget.settings.alignmentFor(
                      presentationElementKey(item.id, 'body'),
                      TextAlign.center,
                    ),
                  ),
            ) +
            math.max(0, captions.length - 1) * 12;
        final reservedGap = captions.isEmpty ? 0.0 : 14.0;
        final imageHeight = math.max(
          120.0,
          availableHeight - captionHeight - reservedGap,
        );
        final imageWidth = math.max(120.0, availableWidth);

        return PresentationOverflowFrame(
          overflow: imageHeight + captionHeight + reservedGap > availableHeight,
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: bodyHeight),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildPresentationHeroImage(
                      primaryMediaRef,
                      width: imageWidth,
                      height: imageHeight,
                    ),
                    for (final item in captions) ...[
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: availableWidth * .9,
                        ),
                        child: _element(
                          item,
                          'body',
                          captionBase,
                          Text(
                            item.displayText.trim(),
                            textAlign: widget.settings.alignmentFor(
                              presentationElementKey(item.id, 'body'),
                              TextAlign.center,
                            ),
                            style: captionStyle.copyWith(
                              fontSize: _elementSize(
                                presentationElementKey(item.id, 'body'),
                                captionBase,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<_PlacementRenderEntry> _placementEntriesForHorizontalSplit(
    PresentationSlide slide,
    PresentationLayoutPreference layoutPreference, {
    required bool forLeftRegion,
  }) {
    final entries = <_PlacementRenderEntry>[];
    final textOnLeft =
        layoutPreference != PresentationLayoutPreference.imageLeftTextRight;
    for (final item in slide.items) {
      final hasText = _hasTextContent(item);
      final hasMedia = _hasMediaContent(item);
      final explicitPlacement = item.itemPlacement;
      final explicitRegion = presentationItemPlacementToLayoutRegion(
        explicitPlacement,
      );

      if (explicitPlacement != PresentationItemPlacement.auto) {
        final goesLeft = switch (explicitRegion) {
          PresentationLayoutRegion.left ||
          PresentationLayoutRegion.main ||
          PresentationLayoutRegion.sidebar ||
          PresentationLayoutRegion.caption ||
          PresentationLayoutRegion.full => true,
          PresentationLayoutRegion.right ||
          PresentationLayoutRegion.background ||
          PresentationLayoutRegion.overlay ||
          PresentationLayoutRegion.top ||
          PresentationLayoutRegion.bottom ||
          PresentationLayoutRegion.footer => false,
        };
        if (goesLeft != forLeftRegion) continue;
        entries.add(
          _PlacementRenderEntry(
            item: item,
            renderText: hasText,
            renderMedia: hasMedia,
          ),
        );
        continue;
      }

      final isSplitMedia = _isHorizontalSplitLayout(layoutPreference);
      if (forLeftRegion) {
        if (textOnLeft) {
          if (hasText) {
            entries.add(
              _PlacementRenderEntry(
                item: item,
                renderText: true,
                renderMedia: !isSplitMedia && hasMedia,
              ),
            );
          }
        } else if (hasMedia) {
          entries.add(
            _PlacementRenderEntry(
              item: item,
              renderText: false,
              renderMedia: true,
            ),
          );
        }
      } else {
        if (textOnLeft) {
          if (hasMedia) {
            entries.add(
              _PlacementRenderEntry(
                item: item,
                renderText: false,
                renderMedia: true,
              ),
            );
          }
        } else if (hasText) {
          entries.add(
            _PlacementRenderEntry(
              item: item,
              renderText: true,
              renderMedia: !isSplitMedia && hasMedia,
            ),
          );
        }
      }
    }
    return entries;
  }

  List<_PlacementRenderEntry> _placementEntriesForVerticalSplit(
    PresentationSlide slide,
    PresentationLayoutPreference layoutPreference, {
    required bool forTopRegion,
  }) {
    final entries = <_PlacementRenderEntry>[];
    final textOnTop =
        layoutPreference != PresentationLayoutPreference.imageTopTextBottom;
    for (final item in slide.items) {
      final hasText = _hasTextContent(item);
      final hasMedia = _hasMediaContent(item);
      final explicitPlacement = item.itemPlacement;
      final explicitRegion = presentationItemPlacementToLayoutRegion(
        explicitPlacement,
      );

      if (explicitPlacement != PresentationItemPlacement.auto) {
        final goesTop = switch (explicitRegion) {
          PresentationLayoutRegion.top ||
          PresentationLayoutRegion.main ||
          PresentationLayoutRegion.sidebar ||
          PresentationLayoutRegion.caption ||
          PresentationLayoutRegion.full => true,
          PresentationLayoutRegion.bottom ||
          PresentationLayoutRegion.left ||
          PresentationLayoutRegion.right ||
          PresentationLayoutRegion.background ||
          PresentationLayoutRegion.overlay ||
          PresentationLayoutRegion.footer => false,
        };
        if (goesTop != forTopRegion) continue;
        entries.add(
          _PlacementRenderEntry(
            item: item,
            renderText: hasText,
            renderMedia: hasMedia,
          ),
        );
        continue;
      }

      if (forTopRegion) {
        if (textOnTop) {
          if (hasText) {
            entries.add(
              _PlacementRenderEntry(
                item: item,
                renderText: true,
                renderMedia: false,
              ),
            );
          }
        } else if (hasMedia) {
          entries.add(
            _PlacementRenderEntry(
              item: item,
              renderText: false,
              renderMedia: true,
            ),
          );
        }
      } else {
        if (textOnTop) {
          if (hasMedia) {
            entries.add(
              _PlacementRenderEntry(
                item: item,
                renderText: false,
                renderMedia: true,
              ),
            );
          }
        } else if (hasText) {
          entries.add(
            _PlacementRenderEntry(
              item: item,
              renderText: true,
              renderMedia: false,
            ),
          );
        }
      }
    }
    return entries;
  }

  Widget _renderPlacementEntries(
    List<_PlacementRenderEntry> entries, {
    required String slideTitle,
    required TextStyle bodyStyle,
    required TextStyle noteTextStyle,
    required TextStyle headingStyle,
    required double bodyFontSize,
    required TextAlign bodyTextAlign,
    required bool includeSpacing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          _zoneItemWidget(
            item: entries[i].item,
            renderText: entries[i].renderText,
            renderMedia: entries[i].renderMedia,
            slideTitle: slideTitle,
            bodyStyle: bodyStyle,
            noteTextStyle: noteTextStyle,
            headingStyle: headingStyle,
            bodyFontSize: bodyFontSize,
            bodyTextAlign: bodyTextAlign,
          ),
          if (includeSpacing && i < entries.length - 1)
            const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _placementZone(
    List<_PlacementRenderEntry> entries, {
    required PresentationSlide slide,
    required TextStyle bodyStyle,
    required TextStyle noteTextStyle,
    required TextStyle headingStyle,
    required double minFontSize,
    required double maxFontSize,
    required TextAlign alignment,
    required ScrollController controller,
    required String area,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textItems = entries
            .where((e) => e.renderText)
            .map((e) => e.item)
            .toList();
        final textSlide = PresentationSlide(
          id: slide.id,
          settingsKey: slide.settingsKey,
          slideNumber: slide.slideNumber,
          layoutType: slide.layoutType,
          slideTitle: slide.slideTitle,
          items: textItems,
        );
        final size = _chosenBodyFontSize(
          slide: textSlide,
          bodyStyle: bodyStyle,
          noteTextStyle: noteTextStyle,
          bodyMinFontSize: minFontSize,
          bodyMaxFontSize: maxFontSize,
          bodyWidth: constraints.maxWidth,
          bodyHeight: constraints.maxHeight,
          textDirection: Directionality.of(context),
          bodyTextAlign: alignment,
        );
        final overflow =
            _renderedTextHeight(
              textSlide,
              constraints.maxWidth,
              size,
              bodyStyle,
              noteTextStyle,
              headingStyle,
              alignment,
            ) >
            constraints.maxHeight;
        return PresentationOverflowFrame(
          overflow: overflow,
          area: area,
          child: SingleChildScrollView(
            controller: controller,
            primary: false,
            child: _renderPlacementEntries(
              entries,
              slideTitle: slide.slideTitle?.trim() ?? '',
              bodyStyle: bodyStyle,
              noteTextStyle: noteTextStyle,
              headingStyle: headingStyle,
              bodyFontSize: size,
              bodyTextAlign: alignment,
              includeSpacing: true,
            ),
          ),
        );
      },
    );
  }

  Widget _buildHorizontalSplitSlideBody({
    required BuildContext context,
    required PresentationSlide slide,
    required TextStyle bodyStyle,
    required TextStyle noteTextStyle,
    required TextStyle headingStyle,
    required double bodyMinFontSize,
    required double bodyMaxFontSize,
    required PresentationLayoutPreference layoutPreference,
  }) {
    final bodyTextAlign = _bodyTextAlign(slide);
    final leftEntries = _placementEntriesForHorizontalSplit(
      slide,
      layoutPreference,
      forLeftRegion: true,
    );
    final rightEntries = _placementEntriesForHorizontalSplit(
      slide,
      layoutPreference,
      forLeftRegion: false,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 22),
      child: LayoutBuilder(
        builder: (context, bodyConstraints) {
          final leftShare = switch (layoutPreference) {
            PresentationLayoutPreference
                .textLeftThreeQuarterImageRightOneQuarter =>
              0.75,
            PresentationLayoutPreference.textLeftTwoThirdsImageRightOneThird =>
              0.67,
            PresentationLayoutPreference.imageLeftTextRight => 0.35,
            _ => 0.70,
          };
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: (leftShare * 100).round().clamp(1, 99),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF101319).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE0BE87).withValues(alpha: 0.12),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: _placementZone(
                    leftEntries,
                    slide: slide,
                    bodyStyle: bodyStyle,
                    noteTextStyle: noteTextStyle,
                    headingStyle: headingStyle,
                    minFontSize: bodyMinFontSize,
                    maxFontSize: bodyMaxFontSize,
                    alignment: bodyTextAlign,
                    controller: _leftScrollController,
                    area: 'the left text area',
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: ((1.0 - leftShare) * 100).round().clamp(1, 99),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF171B21).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE0BE87).withValues(alpha: 0.18),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: _placementZone(
                    rightEntries,
                    slide: slide,
                    bodyStyle: bodyStyle,
                    noteTextStyle: noteTextStyle,
                    headingStyle: headingStyle,
                    minFontSize: bodyMinFontSize,
                    maxFontSize: bodyMaxFontSize,
                    alignment: bodyTextAlign,
                    controller: _rightScrollController,
                    area: 'the right text area',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVerticalSplitSlideBody({
    required BuildContext context,
    required PresentationSlide slide,
    required TextStyle bodyStyle,
    required TextStyle noteTextStyle,
    required TextStyle headingStyle,
    required double bodyMinFontSize,
    required double bodyMaxFontSize,
    required PresentationLayoutPreference layoutPreference,
  }) {
    final topEntries = _placementEntriesForVerticalSplit(
      slide,
      layoutPreference,
      forTopRegion: true,
    );
    final bottomEntries = _placementEntriesForVerticalSplit(
      slide,
      layoutPreference,
      forTopRegion: false,
    );
    final bodyTextAlign = _bodyTextAlign(slide);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 36),
      child: LayoutBuilder(
        builder: (context, bodyConstraints) {
          final topWeight = switch (layoutPreference) {
            PresentationLayoutPreference.textTopImageBottom => 0.68,
            PresentationLayoutPreference.imageTopTextBottom => 0.32,
            _ => 0.65,
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: (topWeight * 100).round().clamp(1, 99),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF101319).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE0BE87).withValues(alpha: 0.12),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: _placementZone(
                    topEntries,
                    slide: slide,
                    bodyStyle: bodyStyle,
                    noteTextStyle: noteTextStyle,
                    headingStyle: headingStyle,
                    minFontSize: bodyMinFontSize,
                    maxFontSize: bodyMaxFontSize,
                    alignment: bodyTextAlign,
                    controller: _leftScrollController,
                    area: 'the top text area',
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                flex: ((1.0 - topWeight) * 100).round().clamp(1, 99),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF171B21).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE0BE87).withValues(alpha: 0.18),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: _placementZone(
                    bottomEntries,
                    slide: slide,
                    bodyStyle: bodyStyle,
                    noteTextStyle: noteTextStyle,
                    headingStyle: headingStyle,
                    minFontSize: bodyMinFontSize,
                    maxFontSize: bodyMaxFontSize,
                    alignment: bodyTextAlign,
                    controller: _rightScrollController,
                    area: 'the bottom text area',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverlaySlideBody({
    required BuildContext context,
    required PresentationSlide slide,
    required TextStyle bodyStyle,
    required TextStyle noteTextStyle,
    required TextStyle headingStyle,
    required double bodyMinFontSize,
    required double bodyMaxFontSize,
  }) {
    final bodyTextAlign = _bodyTextAlign(slide);
    final backgroundItems = slide.items.where(
      (item) =>
          item.itemPlacement == PresentationItemPlacement.background ||
          (item.itemPlacement == PresentationItemPlacement.auto &&
              _hasMediaContent(item)),
    );
    final overlayItems = slide.items.where(
      (item) => item.itemPlacement == PresentationItemPlacement.auto
          ? _hasTextContent(item)
          : item.itemPlacement == PresentationItemPlacement.full ||
                item.itemPlacement == PresentationItemPlacement.center ||
                item.itemPlacement == PresentationItemPlacement.notes ||
                item.itemPlacement == PresentationItemPlacement.citation,
    );

    final backgroundRef = backgroundItems
        .expand((item) => item.mediaRefs ?? const <String>[])
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    return Stack(
      children: [
        if (backgroundRef.isNotEmpty)
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0B0D11),
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: LayoutBuilder(
                  builder: (context, _) {
                    final resolved = _resolveMediaPath(backgroundRef);
                    if (resolved == null) {
                      return _mediaUnavailablePreview(backgroundRef);
                    }
                    final file = File(resolved);
                    if (!file.existsSync()) {
                      return _mediaUnavailablePreview(backgroundRef);
                    }
                    return Image.file(
                      file,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      errorBuilder: (context, error, stackTrace) {
                        return _mediaUnavailablePreview(backgroundRef);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: _renderPlacementEntries(
                  overlayItems
                      .map((item) {
                        return _PlacementRenderEntry(
                          item: item,
                          renderText: true,
                          renderMedia: false,
                        );
                      })
                      .toList(growable: false),
                  slideTitle: slide.slideTitle?.trim() ?? '',
                  bodyStyle: bodyStyle,
                  noteTextStyle: noteTextStyle,
                  headingStyle: headingStyle,
                  bodyFontSize: bodyMinFontSize,
                  bodyTextAlign: bodyTextAlign,
                  includeSpacing: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresentationHeroImage(
    String relativePath, {
    required double width,
    required double height,
  }) {
    final resolved = _resolveMediaPath(relativePath);
    if (resolved == null) {
      return _mediaUnavailablePreview(relativePath);
    }

    final file = File(resolved);
    if (!file.existsSync()) {
      return _mediaUnavailablePreview(relativePath);
    }

    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFF0F1217)),
            child: Image.file(
              file,
              width: width,
              height: height,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                return _mediaUnavailablePreview(relativePath);
              },
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildTwoColumnSlideBody({
    required BuildContext context,
    required PresentationSlide slide,
    required TextStyle bodyStyle,
    required TextStyle noteTextStyle,
    required TextStyle headingStyle,
    required double bodyMinFontSize,
    required double bodyMaxFontSize,
  }) {
    final verseItems = _verseItems(slide);
    final noteItems = _noteItems(slide);
    if (verseItems.isEmpty || noteItems.isEmpty) {
      return _buildFullWidthSlideBody(
        context: context,
        slide: slide,
        bodyStyle: bodyStyle,
        noteTextStyle: noteTextStyle,
        headingStyle: headingStyle,
        bodyMinFontSize: bodyMinFontSize,
        bodyMaxFontSize: bodyMaxFontSize,
      );
    }

    final bodyTextAlign = _bodyTextAlign(slide);
    final leftText = _twoColumnLeftMeasurementText(slide);
    final rightText = _twoColumnRightMeasurementText(slide);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 22),
      child: LayoutBuilder(
        builder: (context, bodyConstraints) {
          final bodyWidth = math.max(0.0, bodyConstraints.maxWidth);
          final bodyHeight = math.max(0.0, bodyConstraints.maxHeight);
          final gap = 18.0;
          final leftWidth = math.max(0.0, (bodyWidth - gap) * 0.60);
          final rightWidth = math.max(0.0, bodyWidth - gap - leftWidth);

          final leftFontSize = _fitFontSize(
            text: leftText.isEmpty ? slide.slideTitle?.trim() ?? '' : leftText,
            style: bodyStyle,
            maxWidth: math.max(0.0, leftWidth - 36.0),
            maxHeight: math.max(0.0, bodyHeight - 32.0),
            minFontSize: bodyMinFontSize,
            maxFontSize: bodyMaxFontSize,
            textDirection: Directionality.of(context),
            textAlign: bodyTextAlign,
            safetyBuffer: 18.0,
          );
          final noteMinFontSize = 16.0;
          final noteMaxFontSize = math.min(
            56.0,
            math.max(32.0, rightWidth * 0.12),
          );
          final rightFontSize = rightText.isEmpty
              ? leftFontSize
              : _fitFontSize(
                  text: rightText,
                  style: noteTextStyle,
                  maxWidth: math.max(0.0, rightWidth - 36.0),
                  maxHeight: math.max(0.0, bodyHeight - 32.0),
                  minFontSize: noteMinFontSize,
                  maxFontSize: noteMaxFontSize,
                  textDirection: Directionality.of(context),
                  textAlign: bodyTextAlign,
                  safetyBuffer: 18.0,
                );
          final sharedFontSize =
              widget.settings.fontSizeOverride ??
              (widget.settings.autoFitEnabled
                  ? math.min(leftFontSize, rightFontSize)
                  : bodyMinFontSize);
          final leftNeedsScroll =
              _measureTextHeight(
                text: leftText.isEmpty
                    ? slide.slideTitle?.trim() ?? ''
                    : leftText,
                style: bodyStyle.copyWith(fontSize: sharedFontSize),
                maxWidth: math.max(0.0, leftWidth - 36.0),
                textDirection: Directionality.of(context),
                textAlign: bodyTextAlign,
              ) >
              math.max(0.0, bodyHeight - 40.0);

          final rightNeedsScroll =
              _measureTextHeight(
                text: rightText,
                style: noteTextStyle.copyWith(fontSize: sharedFontSize),
                maxWidth: math.max(0.0, rightWidth - 36.0),
                textDirection: Directionality.of(context),
                textAlign: bodyTextAlign,
              ) >
              math.max(0.0, bodyHeight - 40.0);

          Widget buildLeftZone() {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF101319).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFE0BE87).withValues(alpha: 0.12),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: SingleChildScrollView(
                controller: _leftScrollController,
                primary: false,
                physics: leftNeedsScroll
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0.0, bodyHeight - 32.0),
                  ),
                  // Keep the slide content clear of the bottom navigation buttons.
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < verseItems.length; i++) ...[
                          _slideItemWidget(
                            item: verseItems[i],
                            slideTitle: slide.slideTitle?.trim() ?? '',
                            bodyStyle: bodyStyle,
                            noteTextStyle: noteTextStyle,
                            headingStyle: headingStyle,
                            bodyFontSize: sharedFontSize,
                            bodyTextAlign: bodyTextAlign,
                          ),
                          if (i < verseItems.length - 1)
                            const SizedBox(height: 18),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          Widget buildRightZone() {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF171B21).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFE0BE87).withValues(alpha: 0.18),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: SingleChildScrollView(
                controller: _rightScrollController,
                primary: false,
                physics: rightNeedsScroll
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0.0, bodyHeight - 32.0),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < noteItems.length; i++) ...[
                          _element(
                            noteItems[i],
                            noteItems[i].itemKind == PresentationItemKind.note
                                ? 'body'
                                : 'note',
                            sharedFontSize,
                            _presentationNoteSection(
                              noteText:
                                  (noteItems[i].noteText ??
                                          noteItems[i].displayText)
                                      .trim(),
                              textStyle: noteTextStyle.copyWith(
                                fontSize: _elementSize(
                                  presentationElementKey(
                                    noteItems[i].id,
                                    noteItems[i].itemKind ==
                                            PresentationItemKind.note
                                        ? 'body'
                                        : 'note',
                                  ),
                                  sharedFontSize,
                                ),
                              ),
                              noteFormatJson: noteItems[i].noteFormatJson,
                              mediaRefs:
                                  noteItems[i].mediaRefs ?? const <String>[],
                              textAlign: bodyTextAlign,
                            ),
                          ),
                          if (i < noteItems.length - 1)
                            const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: buildLeftZone()),
              const SizedBox(width: 18),
              Expanded(flex: 2, child: buildRightZone()),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slide = _slide;
    final slideTitle = _slideTitle(slide);
    final titleFormatJson = slide.slideTitleFormatJson?.trim() ?? '';
    final effectiveLayout = _effectiveLayoutPreference(slide);
    final background = const Color(0xFF0B0D11);
    final accent = const Color(0xFFE0BE87);

    return LayoutBuilder(
      builder: (context, constraints) {
        final titleStyle = (theme.textTheme.titleMedium ?? const TextStyle())
            .copyWith(
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: 0.2,
              height: 1.08,
            );
        final referenceWidth = math.max(0.0, constraints.maxWidth - 56);
        final titleSize = _elementSize(
          'slide:title',
          _fitFontSize(
            text: slideTitle,
            style: titleStyle,
            maxWidth: referenceWidth,
            maxHeight: 52,
            minFontSize: 14,
            maxFontSize: 24,
            textDirection: Directionality.of(context),
          ),
        );
        final bodyStyle = (theme.textTheme.headlineSmall ?? const TextStyle())
            .copyWith(
              fontWeight: FontWeight.w400,
              color: const Color(0xFFF7F1E5),
              height: 1.18,
              letterSpacing: 0.1,
            );
        final headingStyle = (theme.textTheme.titleSmall ?? const TextStyle())
            .copyWith(
              fontWeight: FontWeight.w800,
              color: accent.withValues(alpha: 0.88),
              height: 1.12,
              letterSpacing: 0.08,
            );
        final bodyMinFontSize = 18.0;
        final bodyMaxFontSize = math.max(
          56.0,
          math.min(constraints.maxWidth, constraints.maxHeight) * 0.7,
        );
        final noteTextStyle = bodyStyle.copyWith(
          color: const Color(0xFFEADCC2),
          height: 1.22,
        );

        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;
        final aspectRatio = widget.aspectRatioPreset.aspectRatio;
        var panelWidth = math.max(0.0, availableWidth - 32);
        var panelHeight = math.max(0.0, availableHeight - 32);
        if (aspectRatio != null && aspectRatio.isFinite && aspectRatio > 0) {
          if (panelWidth / math.max(panelHeight, 1) > aspectRatio) {
            panelWidth = panelHeight * aspectRatio;
          } else {
            panelHeight = panelWidth / aspectRatio;
          }
        }

        final titleIsVisible = slideTitle.trim().isNotEmpty;

        return Container(
          color: background,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints.tightFor(
                  width: panelWidth,
                  height: panelHeight,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF14171D).withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.32),
                      width: 1.1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 28,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (titleIsVisible) ...[
                            PresentationElement(
                              elementKey: 'slide:title',
                              label: 'Heading',
                              defaultFontSize: titleSize,
                              child: _headingViewport(
                                slideTitle,
                                titleStyle.copyWith(fontSize: titleSize),
                                panelWidth - 56,
                                panelHeight,
                                titleFormatJson.isNotEmpty
                                    ? RichText(
                                        textAlign: widget.settings.alignmentFor(
                                          'slide:title',
                                          _alignments(slide).title,
                                        ),
                                        text: TextSpan(
                                          children: buildPresentationTextSpans(
                                            text: slideTitle,
                                            baseStyle: titleStyle.copyWith(
                                              fontSize: titleSize,
                                            ),
                                            formatJson: titleFormatJson,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        slideTitle,
                                        textAlign: widget.settings.alignmentFor(
                                          'slide:title',
                                          _alignments(slide).title,
                                        ),
                                        style: titleStyle.copyWith(
                                          fontSize: titleSize,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          Expanded(
                            child: _isImageOnlyLayout(effectiveLayout)
                                ? _buildImageFocusedSlideBody(
                                    context: context,
                                    slide: slide,
                                    bodyWidth: panelWidth,
                                    bodyHeight: panelHeight,
                                  )
                                : _isOverlayLayout(effectiveLayout)
                                ? _buildOverlaySlideBody(
                                    context: context,
                                    slide: slide,
                                    bodyStyle: bodyStyle,
                                    noteTextStyle: noteTextStyle,
                                    headingStyle: headingStyle,
                                    bodyMinFontSize: bodyMinFontSize,
                                    bodyMaxFontSize: bodyMaxFontSize,
                                  )
                                : _isHorizontalSplitLayout(effectiveLayout)
                                ? _buildHorizontalSplitSlideBody(
                                    context: context,
                                    slide: slide,
                                    bodyStyle: bodyStyle,
                                    noteTextStyle: noteTextStyle,
                                    headingStyle: headingStyle,
                                    bodyMinFontSize: bodyMinFontSize,
                                    bodyMaxFontSize: bodyMaxFontSize,
                                    layoutPreference: effectiveLayout,
                                  )
                                : _isVerticalSplitLayout(effectiveLayout)
                                ? _buildVerticalSplitSlideBody(
                                    context: context,
                                    slide: slide,
                                    bodyStyle: bodyStyle,
                                    noteTextStyle: noteTextStyle,
                                    headingStyle: headingStyle,
                                    bodyMinFontSize: bodyMinFontSize,
                                    bodyMaxFontSize: bodyMaxFontSize,
                                    layoutPreference: effectiveLayout,
                                  )
                                : _buildFullWidthSlideBody(
                                    context: context,
                                    slide: slide,
                                    bodyStyle: bodyStyle,
                                    noteTextStyle: noteTextStyle,
                                    headingStyle: headingStyle,
                                    bodyMinFontSize: bodyMinFontSize,
                                    bodyMaxFontSize: bodyMaxFontSize,
                                  ),
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
      },
    );
  }
}

class _MediaDimensions {
  const _MediaDimensions({required this.width, required this.height});

  final double width;
  final double height;

  double get aspectRatio => width / height;
}

class _PlacementRenderEntry {
  const _PlacementRenderEntry({
    required this.item,
    required this.renderText,
    required this.renderMedia,
  });

  final PresentationSlideItem item;
  final bool renderText;
  final bool renderMedia;
}
