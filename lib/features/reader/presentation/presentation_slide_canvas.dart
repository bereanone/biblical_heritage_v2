import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/presentation/presentation_models.dart';
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
  });

  final PresentationSlide slide;
  final PresentationAspectRatioPreset aspectRatioPreset;
  final Map<int, String> bookNames;
  final PresentationSlideSettings settings;
  final List<String> mediaRootPaths;

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

  String _primaryMeasurementText(PresentationSlide slide) {
    final blocks = <String>[];
    for (final item in slide.items) {
      if (item.itemKind == PresentationItemKind.note) {
        final text = item.displayText.trim();
        if (text.isNotEmpty) {
          blocks.add(text);
        }
        continue;
      }

      final verseText = item.displayText.trim();
      final citationText = item.citationText?.trim().isNotEmpty == true
          ? item.citationText!.trim()
          : _referenceHeadingForItem(item);
      final parts = <String>[];
      if (verseText.isNotEmpty) parts.add(verseText);
      if (citationText.isNotEmpty) parts.add(citationText);
      if (parts.isNotEmpty) {
        blocks.add(parts.join('\n'));
      }
    }
    return blocks.join('\n\n');
  }

  double _attachedNoteReserveHeight({
    required PresentationSlide slide,
    required TextStyle noteStyle,
    required double bodyWidth,
    required TextDirection textDirection,
    required TextAlign bodyTextAlign,
  }) {
    var total = 0.0;
    final noteMeasureWidth = math.max(0.0, bodyWidth - 24.0);

    for (final item in _verseItems(slide)) {
      final verseText = item.displayText.trim();
      final noteText = item.noteText?.trim() ?? '';
      if (noteText.isEmpty || noteText == verseText) {
        continue;
      }

      final textHeight = _measureTextHeight(
        text: noteText,
        style: noteStyle.copyWith(fontSize: 24.0),
        maxWidth: noteMeasureWidth,
        textDirection: textDirection,
        textAlign: bodyTextAlign,
      );
      total += textHeight + 28.0;
    }

    return total;
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

  PresentationLayoutPreference _effectiveLayoutPreference(
    PresentationSlide slide,
  ) {
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
    if (item.itemKind == PresentationItemKind.note) {
      final noteFontSize = item.mediaRefs?.isNotEmpty == true
          ? math.min(bodyFontSize, 30.0)
          : bodyFontSize;
      return _presentationNoteSection(
        noteText: item.displayText,
        textStyle: noteTextStyle.copyWith(fontSize: noteFontSize),
        noteFormatJson: item.noteFormatJson,
        mediaRefs: item.mediaRefs ?? const <String>[],
        textAlign: bodyTextAlign,
      );
    }

    final verseText = item.displayText.trim();
    final noteText = item.noteText?.trim() ?? '';
    final citationText = item.citationText?.trim().isNotEmpty == true
        ? item.citationText!.trim()
        : _referenceHeadingForItem(item);
    final showAttachedNote =
        includeAttachedNote && noteText.isNotEmpty && noteText != verseText;
    final showCitation = citationText.isNotEmpty;
    final attachedNoteFontSize = math.min(bodyFontSize, 24.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (verseText.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 0),
            child: item.displayTextFormatJson?.trim().isNotEmpty == true
                ? RichText(
                    textAlign: bodyTextAlign,
                    text: TextSpan(
                      children: buildPresentationTextSpans(
                        text: verseText,
                        baseStyle: bodyStyle.copyWith(fontSize: bodyFontSize),
                        formatJson: item.displayTextFormatJson,
                      ),
                    ),
                  )
                : Text(
                    verseText,
                    style: bodyStyle.copyWith(fontSize: bodyFontSize),
                    textAlign: bodyTextAlign,
                    softWrap: true,
                  ),
          ),
        if (showCitation) ...[
          const SizedBox(height: 8),
          Text(
            citationText,
            style: headingStyle.copyWith(
              fontSize: math.max(13, bodyFontSize * 0.36),
            ),
            textAlign: bodyTextAlign,
            softWrap: true,
          ),
        ],
        if (showAttachedNote) ...[
          const SizedBox(height: 12),
          _presentationNoteSection(
            noteText: noteText,
            textStyle: noteTextStyle.copyWith(fontSize: attachedNoteFontSize),
            noteFormatJson: item.noteFormatJson,
            mediaRefs: item.mediaRefs ?? const <String>[],
            textAlign: attachedNoteAlign ?? bodyTextAlign,
          ),
        ],
        if (includeMedia &&
            item.mediaRefs?.isNotEmpty == true &&
            !showAttachedNote) ...[
          const SizedBox(height: 12),
          _presentationNoteSection(
            noteText: '',
            textStyle: noteTextStyle.copyWith(fontSize: attachedNoteFontSize),
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
          textAlign: bodyTextAlign,
        );
      }
      return _presentationNoteSection(
        noteText: noteText,
        textStyle: noteTextStyle.copyWith(fontSize: bodyFontSize),
        noteFormatJson: item.noteFormatJson,
        mediaRefs: renderMedia
            ? item.mediaRefs ?? const <String>[]
            : const <String>[],
        textAlign: bodyTextAlign,
      );
    }

    if (!renderText && renderMedia && item.mediaRefs?.isNotEmpty == true) {
      return _presentationNoteSection(
        noteText: '',
        textStyle: noteTextStyle.copyWith(fontSize: bodyFontSize),
        noteFormatJson: null,
        mediaRefs: item.mediaRefs ?? const <String>[],
        textAlign: bodyTextAlign,
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
    final alignment = _defaultBodyAlignment(slide);
    return switch (alignment) {
      PresentationAlignmentPreference.left => TextAlign.left,
      PresentationAlignmentPreference.center => TextAlign.center,
      PresentationAlignmentPreference.right => TextAlign.right,
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
    final override = widget.settings.fontSizeOverride;
    if (override != null) return override;
    if (!widget.settings.autoFitEnabled) return bodyMinFontSize;

    final slideBodyText = _primaryMeasurementText(slide);
    final isNoteOnlySlide = _hasNoteItems(slide) && !_hasVerseItems(slide);
    final bodyTextStyle = isNoteOnlySlide ? noteTextStyle : bodyStyle;
    final horizontalInset = isNoteOnlySlide ? 22.0 : 16.0;
    final verticalInset = isNoteOnlySlide ? 36.0 : 28.0;
    final reservedNoteHeight = isNoteOnlySlide
        ? 0.0
        : _attachedNoteReserveHeight(
            slide: slide,
            noteStyle: noteTextStyle,
            bodyWidth: bodyWidth,
            textDirection: textDirection,
            bodyTextAlign: bodyTextAlign,
          );
    final fitWidth = math.max(0.0, bodyWidth - horizontalInset);
    final fitHeight = math.max(
      0.0,
      bodyHeight - verticalInset - reservedNoteHeight,
    );
    return _fitFontSize(
      text: slideBodyText,
      style: bodyTextStyle,
      maxWidth: fitWidth,
      maxHeight: fitHeight,
      minFontSize: bodyMinFontSize,
      maxFontSize: bodyMaxFontSize,
      textDirection: textDirection,
      textAlign: bodyTextAlign,
      safetyBuffer: isNoteOnlySlide ? 24.0 : 24.0,
    );
  }

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 36),
      child: LayoutBuilder(
        builder: (context, bodyConstraints) {
          final bodyWidth = math.max(0.0, bodyConstraints.maxWidth);
          final bodyHeight = math.max(0.0, bodyConstraints.maxHeight);
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
          final bodyTextStyle = isNoteOnlySlide ? noteTextStyle : bodyStyle;
          final bodyMeasurementText = _primaryMeasurementText(slide);
          final reservedNoteHeight = isNoteOnlySlide
              ? 0.0
              : _attachedNoteReserveHeight(
                  slide: slide,
                  noteStyle: noteTextStyle,
                  bodyWidth: bodyWidth,
                  textDirection: Directionality.of(context),
                  bodyTextAlign: bodyTextAlign,
                );
          final needsInnerScroll =
              isNoteOnlySlide ||
              _measureTextHeight(
                    text: bodyMeasurementText,
                    style: bodyTextStyle.copyWith(
                      fontSize: chosenSlideBodySize,
                    ),
                    maxWidth: math.max(
                      0.0,
                      bodyWidth - (isNoteOnlySlide ? 22.0 : 0.0),
                    ),
                    textDirection: Directionality.of(context),
                    textAlign: bodyTextAlign,
                  ) >
                  math.max(
                    0.0,
                    bodyHeight -
                        (isNoteOnlySlide ? 36.0 : 28.0) -
                        reservedNoteHeight,
                  );

          return SingleChildScrollView(
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
    final captionText = slide.items
        .where((item) => item.itemKind == PresentationItemKind.note)
        .map((item) => item.displayText.trim())
        .where((text) => text.isNotEmpty)
        .join('\n\n');

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
        final captionHeight = captionText.isEmpty
            ? 0.0
            : _measureTextHeight(
                text: captionText,
                style: captionStyle,
                maxWidth: math.max(0.0, availableWidth * 0.92),
                textDirection: Directionality.of(context),
                textAlign: TextAlign.center,
              );
        final reservedGap = captionText.isEmpty ? 0.0 : 14.0;
        final imageHeight = math.max(
          120.0,
          availableHeight - captionHeight - reservedGap,
        );
        final imageWidth = math.max(120.0, availableWidth);

        return ConstrainedBox(
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
                if (captionText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: availableWidth * 0.9),
                    child: Text(
                      captionText,
                      textAlign: TextAlign.center,
                      style: captionStyle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
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
            const SizedBox(height: 18),
        ],
      ],
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
    final leftText = _primaryMeasurementText(
      PresentationSlide(
        id: slide.id,
        settingsKey: slide.settingsKey,
        slideNumber: slide.slideNumber,
        layoutType: slide.layoutType,
        slideTitle: slide.slideTitle,
        slideTitleFormatJson: slide.slideTitleFormatJson,
        legacyGroupKey: slide.legacyGroupKey,
        customLayoutJson: slide.customLayoutJson,
        items: leftEntries.map((entry) => entry.item).toList(growable: false),
      ),
    );
    final rightText = _primaryMeasurementText(
      PresentationSlide(
        id: slide.id,
        settingsKey: slide.settingsKey,
        slideNumber: slide.slideNumber,
        layoutType: slide.layoutType,
        slideTitle: slide.slideTitle,
        slideTitleFormatJson: slide.slideTitleFormatJson,
        legacyGroupKey: slide.legacyGroupKey,
        customLayoutJson: slide.customLayoutJson,
        items: rightEntries.map((entry) => entry.item).toList(growable: false),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 22),
      child: LayoutBuilder(
        builder: (context, bodyConstraints) {
          final bodyWidth = math.max(0.0, bodyConstraints.maxWidth);
          final bodyHeight = math.max(0.0, bodyConstraints.maxHeight);
          final gap = 18.0;
          final leftShare = switch (layoutPreference) {
            PresentationLayoutPreference
                .textLeftThreeQuarterImageRightOneQuarter =>
              0.75,
            PresentationLayoutPreference.textLeftTwoThirdsImageRightOneThird =>
              0.67,
            PresentationLayoutPreference.imageLeftTextRight => 0.35,
            _ => 0.70,
          };
          final leftWidth = math.max(0.0, (bodyWidth - gap) * leftShare);
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
          final rightFontSize = _fitFontSize(
            text: rightText,
            style: noteTextStyle,
            maxWidth: math.max(0.0, rightWidth - 36.0),
            maxHeight: math.max(0.0, bodyHeight - 32.0),
            minFontSize: 16.0,
            maxFontSize: math.min(56.0, math.max(32.0, rightWidth * 0.12)),
            textDirection: Directionality.of(context),
            textAlign: bodyTextAlign,
            safetyBuffer: 18.0,
          );
          final sharedFontSize =
              widget.settings.fontSizeOverride ??
              (widget.settings.autoFitEnabled
                  ? math.min(leftFontSize, rightFontSize)
                  : bodyMinFontSize);
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
                  child: SingleChildScrollView(
                    controller: _leftScrollController,
                    primary: false,
                    physics: const ClampingScrollPhysics(),
                    child: _renderPlacementEntries(
                      leftEntries,
                      slideTitle: slide.slideTitle?.trim() ?? '',
                      bodyStyle: bodyStyle,
                      noteTextStyle: noteTextStyle,
                      headingStyle: headingStyle,
                      bodyFontSize: sharedFontSize,
                      bodyTextAlign: bodyTextAlign,
                      includeSpacing: true,
                    ),
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
                  child: SingleChildScrollView(
                    controller: _rightScrollController,
                    primary: false,
                    physics: const ClampingScrollPhysics(),
                    child: _renderPlacementEntries(
                      rightEntries,
                      slideTitle: slide.slideTitle?.trim() ?? '',
                      bodyStyle: bodyStyle,
                      noteTextStyle: noteTextStyle,
                      headingStyle: headingStyle,
                      bodyFontSize: sharedFontSize,
                      bodyTextAlign: bodyTextAlign,
                      includeSpacing: true,
                    ),
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
    final topText = _primaryMeasurementText(
      PresentationSlide(
        id: slide.id,
        settingsKey: slide.settingsKey,
        slideNumber: slide.slideNumber,
        layoutType: slide.layoutType,
        slideTitle: slide.slideTitle,
        slideTitleFormatJson: slide.slideTitleFormatJson,
        legacyGroupKey: slide.legacyGroupKey,
        customLayoutJson: slide.customLayoutJson,
        items: topEntries.map((entry) => entry.item).toList(growable: false),
      ),
    );
    final bottomText = _primaryMeasurementText(
      PresentationSlide(
        id: slide.id,
        settingsKey: slide.settingsKey,
        slideNumber: slide.slideNumber,
        layoutType: slide.layoutType,
        slideTitle: slide.slideTitle,
        slideTitleFormatJson: slide.slideTitleFormatJson,
        legacyGroupKey: slide.legacyGroupKey,
        customLayoutJson: slide.customLayoutJson,
        items: bottomEntries.map((entry) => entry.item).toList(growable: false),
      ),
    );
    final bodyTextAlign = _bodyTextAlign(slide);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 36),
      child: LayoutBuilder(
        builder: (context, bodyConstraints) {
          final bodyWidth = math.max(0.0, bodyConstraints.maxWidth);
          final bodyHeight = math.max(0.0, bodyConstraints.maxHeight);
          final topWeight = switch (layoutPreference) {
            PresentationLayoutPreference.textTopImageBottom => 0.68,
            PresentationLayoutPreference.imageTopTextBottom => 0.32,
            _ => 0.65,
          };
          final topHeight = math.max(0.0, (bodyHeight - 18.0) * topWeight);
          final bottomHeight = math.max(0.0, bodyHeight - 18.0 - topHeight);
          final topFontSize = _fitFontSize(
            text: topText.isEmpty ? slide.slideTitle?.trim() ?? '' : topText,
            style: bodyStyle,
            maxWidth: math.max(0.0, bodyWidth - 32.0),
            maxHeight: math.max(0.0, topHeight - 24.0),
            minFontSize: bodyMinFontSize,
            maxFontSize: bodyMaxFontSize,
            textDirection: Directionality.of(context),
            textAlign: bodyTextAlign,
            safetyBuffer: 18.0,
          );
          final bottomFontSize = _fitFontSize(
            text: bottomText,
            style: noteTextStyle,
            maxWidth: math.max(0.0, bodyWidth - 32.0),
            maxHeight: math.max(0.0, bottomHeight - 24.0),
            minFontSize: 16.0,
            maxFontSize: math.min(56.0, math.max(32.0, bodyWidth * 0.12)),
            textDirection: Directionality.of(context),
            textAlign: bodyTextAlign,
            safetyBuffer: 18.0,
          );
          final sharedFontSize =
              widget.settings.fontSizeOverride ??
              (widget.settings.autoFitEnabled
                  ? math.min(topFontSize, bottomFontSize)
                  : bodyMinFontSize);

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
                  child: SingleChildScrollView(
                    controller: _leftScrollController,
                    primary: false,
                    physics: const ClampingScrollPhysics(),
                    child: _renderPlacementEntries(
                      topEntries,
                      slideTitle: slide.slideTitle?.trim() ?? '',
                      bodyStyle: bodyStyle,
                      noteTextStyle: noteTextStyle,
                      headingStyle: headingStyle,
                      bodyFontSize: sharedFontSize,
                      bodyTextAlign: bodyTextAlign,
                      includeSpacing: true,
                    ),
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
                  child: SingleChildScrollView(
                    controller: _rightScrollController,
                    primary: false,
                    physics: const ClampingScrollPhysics(),
                    child: _renderPlacementEntries(
                      bottomEntries,
                      slideTitle: slide.slideTitle?.trim() ?? '',
                      bodyStyle: bodyStyle,
                      noteTextStyle: noteTextStyle,
                      headingStyle: headingStyle,
                      bodyFontSize: sharedFontSize,
                      bodyTextAlign: bodyTextAlign,
                      includeSpacing: true,
                    ),
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
                          _presentationNoteSection(
                            noteText:
                                (noteItems[i].noteText ??
                                        noteItems[i].displayText)
                                    .trim(),
                            textStyle: noteTextStyle.copyWith(
                              fontSize: sharedFontSize,
                            ),
                            noteFormatJson: noteItems[i].noteFormatJson,
                            mediaRefs:
                                noteItems[i].mediaRefs ?? const <String>[],
                            textAlign: bodyTextAlign,
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
        final titleSize = _fitFontSize(
          text: slideTitle,
          style: titleStyle,
          maxWidth: referenceWidth,
          maxHeight: 52,
          minFontSize: 14,
          maxFontSize: 24,
          textDirection: Directionality.of(context),
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
        final bodyMaxFontSize = math.min(
          88.0,
          math.max(56.0, constraints.maxWidth * 0.085),
        );
        final noteTextStyle = bodyStyle.copyWith(
          color: const Color(0xFFEADCC2),
          height: 1.22,
        );

        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;
        final aspectRatio = widget.aspectRatioPreset.aspectRatio;
        var panelWidth = availableWidth;
        final panelHeight = availableHeight;
        if (aspectRatio != null && aspectRatio.isFinite && aspectRatio > 0) {
          final ratioWidth = panelHeight * aspectRatio;
          if (ratioWidth <= availableWidth) {
            panelWidth = ratioWidth;
          }
        }
        if (availableWidth <= 0) {
          panelWidth = 0.0;
        } else if (availableWidth < 280.0) {
          panelWidth = math.min(panelWidth, availableWidth);
        } else {
          panelWidth = panelWidth.clamp(280.0, availableWidth).toDouble();
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
                            titleFormatJson.isNotEmpty
                                ? RichText(
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: titleStyle.copyWith(
                                      fontSize: titleSize,
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
