import 'dart:math' as math;
import 'presentation_line_break.dart';
import 'presentation_element.dart';
import '../data/presentation/presentation_slide_settings.dart';
import 'package:flutter/material.dart';
import '../data/presentation/presentation_models.dart';
import '../data/presentation/note_image_layout.dart';
import '../data/presentation/presentation_text_format.dart';

/// Measures the same styled blocks, citations, note insets and gaps the canvas
/// renders. Media is reserved by the caller before supplying a text region.
double presentationTextHeight({
  required PresentationSlide slide,
  PresentationSlideSettings settings = const PresentationSlideSettings(),
  required Map<int, String> bookNames,
  required double width,
  required double fontSize,
  required TextStyle bodyStyle,
  required TextStyle noteStyle,
  required TextStyle headingStyle,
  required TextDirection direction,
  required TextScaler textScaler,
  required TextAlign alignment,
}) {
  double measure(
    String text,
    TextStyle style,
    double w, {
    String? format,
    bool rich = false,
    TextAlign? align,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        children: buildPresentationTextSpans(
          text: text,
          baseStyle: style,
          formatJson: format,
        ),
      ),
      textDirection: direction,
      textAlign: align ?? alignment,
      // Existing formatted RichText uses no system scaling; plain Text does.
      textScaler: rich ? TextScaler.noScaling : textScaler,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(maxWidth: math.max(1, w));
    var height = painter.height;
    for (final line in painter.computeLineMetrics()) {
      final position = painter.getPositionForOffset(
        Offset(0, line.baseline - line.ascent / 2),
      );
      final end = painter.getLineBoundary(position).end;
      if (end > 0 && end < text.length) {
        final word = painter.getWordBoundary(TextPosition(offset: end));
        if ((word.start < end && word.end > end) ||
            presentationBreakOrphansPunctuation(text, end)) {
          height = double.infinity;
          break;
        }
      }
    }
    painter.dispose();
    return height;
  }

  double note(
    String text,
    double size,
    String? format,
    TextAlign noteAlignment,
  ) {
    if (text.trim().isEmpty) return 0;
    final centered = noteAlignment == TextAlign.center;
    return (centered ? 20 : 24) +
        measure(
          text,
          noteStyle.copyWith(fontSize: size),
          width - (centered ? 20 : 28),
          format: format,
          rich: true,
          align: noteAlignment,
        );
  }

  String normalized(String s) =>
      s.trim().replaceAll('–', '-').replaceAll('—', '-');
  var height = 0.0;
  for (var i = 0; i < slide.items.length; i++) {
    if (i > 0) height += 16;
    final item = slide.items[i];
    if (item.itemKind == PresentationItemKind.note) {
      height += note(
        item.displayText,
        settings.fontSizeFor(
          presentationElementKey(item.id, 'body'),
          item.mediaRefs?.isNotEmpty == true
              ? math.min(fontSize, 30)
              : fontSize,
        ),
        item.noteFormatJson,
        settings.alignmentFor(
          presentationElementKey(item.id, 'body'),
          alignment,
        ),
      );
      continue;
    }
    final body = item.displayText.trim();
    if (body.isNotEmpty) {
      height += measure(
        body,
        bodyStyle.copyWith(
          fontSize: settings.fontSizeFor(
            presentationElementKey(item.id, 'body'),
            fontSize,
          ),
        ),
        width,
        align: settings.alignmentFor(
          presentationElementKey(item.id, 'body'),
          alignment,
        ),
        format: item.displayTextFormatJson,
        rich: item.displayTextFormatJson?.trim().isNotEmpty == true,
      );
    }
    final fallback =
        item.bookNumber <= 0 || item.chapter <= 0 || item.verse <= 0
        ? ''
        : '${bookNames[item.bookNumber] ?? 'Book ${item.bookNumber}'} ${item.chapter}:${item.verse}${item.verseEnd > item.verse ? '-${item.verseEnd}' : ''}';
    final citation = item.citationText?.trim().isNotEmpty == true
        ? item.citationText!.trim()
        : fallback;
    if (citation.isNotEmpty &&
        normalized(citation) != normalized(slide.slideTitle ?? '')) {
      height +=
          8 +
          measure(
            citation,
            headingStyle.copyWith(
              fontSize: settings.fontSizeFor(
                presentationElementKey(item.id, 'citation'),
                math.max(13, fontSize * .36),
              ),
            ),
            width,
            align: settings.alignmentFor(
              presentationElementKey(item.id, 'citation'),
              PresentationBlockAlignments.fromFormat(
                item.noteFormatJson,
              ).citation,
            ),
          );
    }
    final attached = item.noteText?.trim() ?? '';
    if (attached.isNotEmpty && attached != body) {
      height +=
          12 +
          note(
            attached,
            settings.fontSizeFor(
              presentationElementKey(item.id, 'note'),
              math.min(fontSize, 24),
            ),
            item.noteFormatJson,
            settings.alignmentFor(
              presentationElementKey(item.id, 'note'),
              alignment,
            ),
          );
    }
  }
  return height;
}

/// Overflow is explicit; retain readable text and make every word reachable.
class PresentationOverflowFrame extends StatefulWidget {
  const PresentationOverflowFrame({
    super.key,
    required this.overflow,
    required this.child,
    this.area = 'this screen',
  });
  final bool overflow;
  final Widget child;
  final String area;
  @override
  State<PresentationOverflowFrame> createState() =>
      _PresentationOverflowFrameState();
}

class _PresentationOverflowFrameState extends State<PresentationOverflowFrame> {
  bool _contentOverflow = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Also catch asynchronous images or explicit mixed-media placement whose
      // final rendered size cannot be known by the text measurer in advance.
      final showWarning = widget.overflow || _contentOverflow;
      return NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth != 0 ||
              notification.metrics.axis != Axis.vertical)
            return false;
          final metrics = notification.metrics;
          final overflow =
              metrics.maxScrollExtent + metrics.viewportDimension >
              constraints.maxHeight + 1;
          if (overflow != _contentOverflow) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && overflow != _contentOverflow)
                setState(() => _contentOverflow = overflow);
            });
          }
          return false;
        },
        child: showWarning
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Text exceeds ${widget.area}. Split this slide or reduce the image area.',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        color: Color(0xFFFFCF80),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: widget.child),
                ],
              )
            : widget.child,
      );
    },
  );
}
