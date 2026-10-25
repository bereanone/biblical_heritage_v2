import 'dart:math' as math;
import 'presentation_line_break.dart';
import 'presentation_element.dart';
import 'presentation_image_element.dart';
import '../data/presentation/presentation_slide_settings.dart';
import 'package:flutter/material.dart';
import '../data/presentation/note_image_layout.dart';
import '../data/presentation/presentation_text_format.dart';

class NoteFlowLine {
  NoteFlowLine(this.painter, this.offset, this.start, this.end);
  final TextPainter painter;
  final Offset offset;
  final int start, end;
}

class NoteFlowPlan {
  NoteFlowPlan(this.lines, this.consumed, this.length);
  final List<NoteFlowLine> lines;
  final int consumed, length;
  bool get fits => consumed == length;
  void dispose() {
    for (final line in lines) {
      line.painter.dispose();
    }
  }
}

List<TextSpan> _slice(List<TextSpan> spans, int start, int end) {
  final result = <TextSpan>[];
  var offset = 0;
  for (final span in spans) {
    final text = span.text ?? '';
    final a = math.max(start - offset, 0);
    final b = math.min(end - offset, text.length);
    if (b > a)
      result.add(TextSpan(text: text.substring(a, b), style: span.style));
    offset += text.length;
    if (offset >= end) break;
  }
  return result;
}

/// Lay out complete first lines in the horizontal space outside an image.
/// Ranges are measured by TextPainter, so wrapping follows Flutter's Unicode
/// boundaries rather than splitting a string into guessed word widths.
NoteFlowPlan planNoteImageFlow({
  required String text,
  required String? formatJson,
  required TextStyle style,
  required Size size,
  required Rect imageRect,
  TextDirection direction = TextDirection.ltr,
  TextAlign alignment = TextAlign.left,
  double gap = 10,
}) {
  final spans = buildPresentationTextSpans(
    text: text,
    baseStyle: style,
    formatJson: formatJson,
  ).cast<TextSpan>();
  final probe = TextPainter(
    text: TextSpan(text: 'Ag', style: style),
    textDirection: direction,
    strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
  )..layout();
  final lineHeight = probe.height;
  probe.dispose();
  if (lineHeight <= 0 ||
      !lineHeight.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    return NoteFlowPlan([], 0, text.length);
  }
  final exclusion = imageRect.inflate(gap).intersect(Offset.zero & size);
  final lines = <NoteFlowLine>[];
  var cursor = 0;
  var y = 0.0;
  while (cursor < text.length && y + lineHeight <= size.height + 0.01) {
    final intersects = y < exclusion.bottom && y + lineHeight > exclusion.top;
    var slots = <Rect>[
      if (!intersects)
        Rect.fromLTWH(0, y, size.width, lineHeight)
      else ...[
        if (exclusion.left > 0) Rect.fromLTWH(0, y, exclusion.left, lineHeight),
        if (exclusion.right < size.width)
          Rect.fromLTWH(
            exclusion.right,
            y,
            size.width - exclusion.right,
            lineHeight,
          ),
      ],
    ];
    if (direction == TextDirection.rtl) slots = slots.reversed.toList();
    var used = false;
    for (final slot in slots) {
      if (cursor >= text.length) break;
      if (slot.width < (style.fontSize ?? 16) * 1.5) continue;
      final remaining = _slice(spans, cursor, text.length);
      final measure = TextPainter(
        text: TextSpan(children: remaining),
        textDirection: direction,
        strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
      )..layout(maxWidth: slot.width);
      final boundary = measure.getLineBoundary(const TextPosition(offset: 0));
      var count = boundary.end.clamp(0, text.length - cursor);
      // A forced character wrap must not make an oversized font appear to fit.
      // Leave the whole word for a wider slot (or a smaller fitting font).
      var backedUpToWord = false;
      if (count > 0 && count < text.length - cursor) {
        final word = measure.getWordBoundary(TextPosition(offset: count));
        if (word.start < count && word.end > count) {
          count = word.start;
          backedUpToWord = true;
        }
        final remainingText = text.substring(cursor);
        while (count > 0 &&
            presentationBreakOrphansPunctuation(remainingText, count)) {
          final preceding = measure.getWordBoundary(
            TextPosition(offset: count - 1),
          );
          count = preceding.start < count ? preceding.start : count - 1;
          backedUpToWord = true;
        }
      }
      measure.dispose();
      if (count == 0 && text[cursor] != '\n') continue;
      // Include a consumed explicit paragraph break in the stored text range.
      if (cursor + count < text.length && text[cursor + count] == '\n') count++;
      final painter = TextPainter(
        text: TextSpan(
          children:
              alignment == TextAlign.justify &&
                  !backedUpToWord &&
                  cursor + count < text.length &&
                  !text.substring(cursor, cursor + count).endsWith('\n')
              ? remaining
              : _slice(spans, cursor, cursor + count),
        ),
        textDirection: direction,
        textAlign: alignment,
        maxLines: 1,
        strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
      )..layout(maxWidth: slot.width);
      lines.add(
        NoteFlowLine(painter, Offset(slot.left, y), cursor, cursor + count),
      );
      cursor += count;
      used = true;
    }
    if (!used && intersects)
      y = math.max(y + lineHeight, exclusion.bottom);
    else
      y += lineHeight;
  }
  return NoteFlowPlan(lines, cursor, text.length);
}

/// Shared by the image-layout preview and the actual presentation.
class NoteImageFlow extends StatefulWidget {
  const NoteImageFlow({
    super.key,
    required this.text,
    required this.formatJson,
    required this.layout,
    required this.image,
    required this.style,
    this.aspectRatio,
    this.minimumDisplayedFontSize,
    this.displayedFontSizeOverride,
    this.onDisplayedFontSizeResolved,
    this.elementItemId,
    this.footerElementPart = 'footer',
    this.elementFontSizes = const {},
    this.elementAlignments = const {},
  });
  final String text;
  final String? formatJson;
  final NoteImageLayout layout;
  final Widget image;
  final TextStyle style;
  final double? aspectRatio;

  /// Presentation targets enforce readability; a small editor preview only scales geometry.
  final double? minimumDisplayedFontSize;
  final double? displayedFontSizeOverride;
  final ValueChanged<double>? onDisplayedFontSizeResolved;
  final String? elementItemId;
  final String footerElementPart;
  final Map<String, double> elementFontSizes;
  final Map<String, PresentationAlignmentPreference> elementAlignments;
  @override
  State<NoteImageFlow> createState() => _NoteImageFlowState();
}

class _NoteImageFlowState extends State<NoteImageFlow> {
  NoteFlowPlan? _plan;
  @override
  void dispose() {
    _plan?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, outer) {
      if (!outer.maxWidth.isFinite ||
          !outer.maxHeight.isFinite ||
          outer.maxWidth <= 0 ||
          outer.maxHeight <= 0)
        return const SizedBox.shrink();
      final stageWidth =
          1080 * (widget.aspectRatio ?? widget.layout.aspectRatio);
      final scale = math.min(
        outer.maxWidth / stageWidth,
        outer.maxHeight / 1080,
      );
      // Keep authored image geometry, but judge readability at displayed size.
      final minimum = widget.minimumDisplayedFontSize == null
          ? 24.0
          : widget.minimumDisplayedFontSize! / scale;
      return FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 1080 * (widget.aspectRatio ?? widget.layout.aspectRatio),
          height: 1080,
          child: _buildStage(context, minimum, scale),
        ),
      );
    },
  );

  Widget _element(String part, String label, double font, Widget child) {
    final id = widget.elementItemId;
    if (id == null) return child;
    return PresentationElement(
      elementKey: presentationElementKey(
        id,
        part == 'footer' ? widget.footerElementPart : part,
      ),
      label: label,
      defaultFontSize: font,
      child: child,
    );
  }

  double? _size(String part) => widget.elementItemId == null
      ? null
      : widget.elementFontSizes[presentationElementKey(
          widget.elementItemId!,
          part == 'footer' ? widget.footerElementPart : part,
        )];

  TextAlign _alignment(String part, TextAlign fallback) {
    final value = widget.elementItemId == null
        ? null
        : widget.elementAlignments[presentationElementKey(
            widget.elementItemId!,
            part == 'footer' ? widget.footerElementPart : part,
          )];
    return value == null ? fallback : presentationAlignmentTextAlign(value);
  }

  Widget _buildStage(
    BuildContext context,
    double minimum,
    double scale,
  ) => LayoutBuilder(
    builder: (context, c) {
      final width = c.maxWidth, height = c.maxHeight;
      if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0)
        return const SizedBox.shrink();
      final headerFont = (_size('header') ?? 42 * scale) / scale;
      final footerFont = (_size('footer') ?? 36 * scale) / scale;
      final headerHeight = widget.layout.header.trim().isEmpty
          ? 0.0
          : math.max(64.0, headerFont * 1.3);
      final footerHeight = widget.layout.footer.trim().isEmpty
          ? 0.0
          : math.max(64.0, footerFont * 1.3);
      final bodyHeight = math.max(0.0, height - headerHeight - footerHeight);
      final size = Size(width, bodyHeight);
      final rect = widget.layout.imageRect(size);
      Widget editableImage() => widget.elementItemId == null
          ? ClipRect(child: widget.image)
          : PresentationImageElement(itemId: widget.elementItemId!, layout: widget.layout,
              stageSize: size, scale: scale, child: ClipRect(child: widget.image));
      final direction = Directionality.of(context);
      NoteFlowPlan compute(double fontSize) => planNoteImageFlow(
        text: widget.text,
        formatJson: widget.formatJson,
        style: widget.style.copyWith(fontSize: fontSize),
        size: size,
        imageRect: rect,
        gap: widget.layout.textGap,
        direction: direction,
        alignment: _alignment(
          'body',
          PresentationBlockAlignments.fromFormat(widget.formatJson).body,
        ),
      );
      final maxFont = math.max(minimum, math.min(width, bodyHeight) * 0.9);
      final override = _size('body') ?? widget.displayedFontSizeOverride;
      var chosen = compute(override == null ? maxFont : override / scale);
      var resolvedFont = override == null ? maxFont : override / scale;
      if (override == null && !chosen.fits) {
        chosen.dispose();
        var low = minimum, high = maxFont;
        for (var i = 0; i < 8; i++) {
          final mid = (low + high) / 2;
          final trial = compute(mid);
          if (trial.fits)
            low = mid;
          else
            high = mid;
          trial.dispose();
        }
        chosen = compute(low);
        resolvedFont = low;
      }
      widget.onDisplayedFontSizeResolved?.call(resolvedFont * scale);
      _plan?.dispose();
      _plan = chosen;
      if (!chosen.fits) {
        // Never silently omit text if no readable font fits the reservation.
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (headerHeight > 0)
                _element(
                  'header',
                  'Note heading',
                  42 * scale,
                  Text(
                    widget.layout.header,
                    style: widget.style.copyWith(fontSize: headerFont),
                  ),
                ),
              Text(
                'Text exceeds this layout. Reduce the image area or split this slide.',
                style: widget.style.copyWith(fontSize: minimum * .75),
              ),
              SizedBox(
                height: math.min(bodyHeight / 3, 160),
                child: editableImage(),
              ),
              _element(
                'body',
                'Note',
                widget.displayedFontSizeOverride ?? resolvedFont * scale,
                RichText(
                  textAlign: _alignment(
                    'body',
                    PresentationBlockAlignments.fromFormat(
                      widget.formatJson,
                    ).body,
                  ),
                  text: TextSpan(
                    children: buildPresentationTextSpans(
                      text: widget.text,
                      formatJson: widget.formatJson,
                      baseStyle: widget.style.copyWith(fontSize: resolvedFont),
                    ),
                  ),
                ),
              ),
              if (footerHeight > 0)
                _element(
                  'footer',
                  'Note footer',
                  36 * scale,
                  Text(
                    widget.layout.footer,
                    style: widget.style.copyWith(fontSize: footerFont),
                  ),
                ),
            ],
          ),
        );
      }
      return Column(
        children: [
          if (headerHeight > 0)
            _element(
              'header',
              'Note heading',
              42 * scale,
              SizedBox(
                height: headerHeight,
                width: width,
                child: Text(
                  widget.layout.header,
                  textAlign: _alignment(
                    'header',
                    PresentationBlockAlignments.fromFormat(
                      widget.formatJson,
                    ).title,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: widget.style.copyWith(fontSize: headerFont),
                ),
              ),
            ),
          SizedBox(
            width: width,
            height: bodyHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: _element(
                    'body',
                    'Note',
                    widget.displayedFontSizeOverride ?? resolvedFont * scale,
                    Semantics(
                      label: widget.text,
                      child: CustomPaint(painter: _FlowPainter(chosen)),
                    ),
                  ),
                ),
                if (widget.elementItemId != null &&
                    PresentationElementScope.maybeOf(context)?.selected == presentationElementKey(widget.elementItemId!, 'image') &&
                    PresentationElementScope.maybeOf(context)?.editing == true)
                  Positioned.fromRect(
                    rect: rect.inflate(widget.layout.textGap),
                    child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
                      color: const Color(0x18E0BE87),
                      border: Border.all(color: const Color(0xFFE0BE87), width: 1 / scale),
                    ))),
                  ),
                Positioned.fromRect(
                  rect: rect,
                  child: editableImage(),
                ),
              ],
            ),
          ),
          if (footerHeight > 0)
            _element(
              'footer',
              'Note footer',
              36 * scale,
              SizedBox(
                height: footerHeight,
                width: width,
                child: Text(
                  widget.layout.footer,
                  textAlign: _alignment(
                    'footer',
                    PresentationBlockAlignments.fromFormat(
                      widget.formatJson,
                    ).footer,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: widget.style.copyWith(fontSize: footerFont),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.plan);
  final NoteFlowPlan plan;
  @override
  void paint(Canvas canvas, Size size) {
    for (final line in plan.lines) {
      line.painter.paint(canvas, line.offset);
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter oldDelegate) =>
      oldDelegate.plan != plan;
}
