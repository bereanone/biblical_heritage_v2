import 'dart:math' as math;
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
      measure.dispose();
      if (count == 0 && text[cursor] != '\n') continue;
      // Include a consumed explicit paragraph break in the stored text range.
      if (cursor + count < text.length && text[cursor + count] == '\n') count++;
      final painter = TextPainter(
        text: TextSpan(
          children:
              alignment == TextAlign.justify &&
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
  });
  final String text;
  final String? formatJson;
  final NoteImageLayout layout;
  final Widget image;
  final TextStyle style;
  final double? aspectRatio;
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
      return FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 1080 * (widget.aspectRatio ?? widget.layout.aspectRatio),
          height: 1080,
          child: _buildStage(context),
        ),
      );
    },
  );

  Widget _buildStage(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final width = c.maxWidth, height = c.maxHeight;
      if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0)
        return const SizedBox.shrink();
      final headerHeight = widget.layout.header.trim().isEmpty ? 0.0 : 64.0;
      final footerHeight = widget.layout.footer.trim().isEmpty ? 0.0 : 64.0;
      final bodyHeight = math.max(0.0, height - headerHeight - footerHeight);
      final size = Size(width, bodyHeight);
      final rect = widget.layout.imageRect(size);
      final direction = Directionality.of(context);
      NoteFlowPlan compute(double fontSize) => planNoteImageFlow(
        text: widget.text,
        formatJson: widget.formatJson,
        style: widget.style.copyWith(fontSize: fontSize),
        size: size,
        imageRect: rect,
        direction: direction,
        alignment: PresentationBlockAlignments.fromFormat(
          widget.formatJson,
        ).body,
      );
      final maxFont = math.max(24.0, math.min(width, bodyHeight) * 0.9);
      var chosen = compute(maxFont);
      if (!chosen.fits) {
        chosen.dispose();
        var low = 24.0, high = maxFont;
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
      }
      _plan?.dispose();
      _plan = chosen;
      if (!chosen.fits) {
        // Never silently omit text if no readable font fits the reservation.
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Text exceeds this layout. Reduce the image area or shorten the note.',
              ),
              SizedBox(
                height: math.min(bodyHeight / 3, 160),
                child: widget.image,
              ),
              RichText(
                text: TextSpan(
                  children: buildPresentationTextSpans(
                    text: widget.text,
                    formatJson: widget.formatJson,
                    baseStyle: widget.style.copyWith(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return Column(
        children: [
          if (headerHeight > 0)
            SizedBox(
              height: headerHeight,
              width: width,
              child: Text(
                widget.layout.header,
                textAlign: PresentationBlockAlignments.fromFormat(
                  widget.formatJson,
                ).title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.style.copyWith(fontSize: 42),
              ),
            ),
          SizedBox(
            width: width,
            height: bodyHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    label: widget.text,
                    child: CustomPaint(painter: _FlowPainter(chosen)),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRect(child: widget.image),
                ),
              ],
            ),
          ),
          if (footerHeight > 0)
            SizedBox(
              height: footerHeight,
              width: width,
              child: Text(
                widget.layout.footer,
                textAlign: PresentationBlockAlignments.fromFormat(
                  widget.formatJson,
                ).footer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.style.copyWith(fontSize: 36),
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
