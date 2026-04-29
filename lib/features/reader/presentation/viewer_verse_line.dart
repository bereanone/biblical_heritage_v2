import 'package:flutter/material.dart';

import '../data/highlights_repository.dart';
import 'viewer_passage_models.dart';
import 'highlight_render.dart';
import 'viewer_markup_span_builder.dart';
import 'viewer_range_selection.dart';
import 'viewer_selection_style.dart';

class ViewerVerseLine extends StatelessWidget {
  const ViewerVerseLine({
    super.key,
    required this.line,
    required this.style,
    required this.isSelected,
    this.showChapterNumber = false,
    this.startsInRedLetter = false,
    this.isTagged = false,
    this.highlight,
    this.tokenHighlights = const <VerseHighlightRecord>[],
    this.isRangeSelected = false,
    required this.onTap,
    this.onVerseNumberLongPress,
    this.rangeSelection,
    this.onTokenLongPress,
  });

  final VerseLine line;
  final TextStyle style;
  final bool isSelected;
  final bool showChapterNumber;
  final bool startsInRedLetter;
  final bool isTagged;
  final VerseHighlightRecord? highlight;
  final List<VerseHighlightRecord> tokenHighlights;
  final bool isRangeSelected;
  final VoidCallback onTap;
  final VoidCallback? onVerseNumberLongPress;
  final ViewerRangeSelection? rangeSelection;
  final ValueChanged<int>? onTokenLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textDirection = Directionality.of(context);
    final brightness = theme.brightness;
    final redLetterColor = brightness == Brightness.dark
        ? const Color(0xFFFF3B30)
        : const Color(0xFFC62828);
    final chapterStyle = style.copyWith(
      fontSize: 24 * (1 + (fontScaleFromStyle(style) - 1) * 0.5),
      fontWeight: FontWeight.w500,
      height: 1.0,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
    );
    final numberStyle = style.copyWith(
      fontSize: 12 * fontScaleFromStyle(style),
      fontWeight: isTagged ? FontWeight.w700 : FontWeight.w600,
      height: 1,
      color: theme.colorScheme.onSurface.withValues(
        alpha: isTagged ? 0.94 : 0.56,
      ),
    );
    final highlightSpec = highlight == null
        ? null
        : resolveHighlightRender(
            highlight!.color,
            brightness == Brightness.dark,
          );
    final baseTextColor =
        highlightSpec?.textColor ?? theme.colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: isSelected
                ? viewerSelectedVerseColor(context)
                : isRangeSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.10)
                : highlightSpec?.backgroundColor ?? Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _VerseGutter(
                chapter: line.chapter,
                verse: line.verse,
                showVerseNumber: !showChapterNumber,
                showChapterNumber: showChapterNumber,
                chapterStyle: chapterStyle,
                numberStyle: numberStyle,
                isTagged: isTagged,
                textDirection: textDirection,
                onLongPress: onVerseNumberLongPress,
              ),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    children: [
                      buildViewerMarkupSpan(
                        html: line.html,
                        fallbackText: line.text,
                        baseStyle: style.copyWith(color: baseTextColor),
                        redLetterColor: redLetterColor,
                        startsInRedLetter: startsInRedLetter,
                        blockId: line.blockId,
                        rangeSelection: rangeSelection,
                        onTokenLongPress: onTokenLongPress,
                        persistedHighlights: tokenHighlights,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double fontScaleFromStyle(TextStyle style) {
  final size = style.fontSize ?? 16;
  return size / 16;
}

class _VerseGutter extends StatelessWidget {
  const _VerseGutter({
    required this.chapter,
    required this.verse,
    required this.showVerseNumber,
    required this.showChapterNumber,
    required this.chapterStyle,
    required this.numberStyle,
    required this.isTagged,
    required this.textDirection,
    this.onLongPress,
  });

  final int chapter;
  final int verse;
  final bool showVerseNumber;
  final bool showChapterNumber;
  final TextStyle chapterStyle;
  final TextStyle numberStyle;
  final bool isTagged;
  final TextDirection textDirection;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final verseWidth = _measureTextWidth('$verse', numberStyle, textDirection);
    final chapterWidth = showChapterNumber
        ? _measureTextWidth('$chapter', chapterStyle, textDirection)
        : 0.0;
    final badgePadding = isTagged ? 10.0 : 0.0;
    final contentWidth = showChapterNumber
        ? (chapterWidth > verseWidth + badgePadding
              ? chapterWidth
              : verseWidth + badgePadding)
        : verseWidth + badgePadding;
    final width = contentWidth + 12.0;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: onLongPress,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsets.only(
            left: showChapterNumber ? 5 : 6,
            right: 6,
            top: 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showChapterNumber)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '$chapter',
                    style: chapterStyle,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                  ),
                ),
              _VerseNumberBadge(
                verse: verse,
                showVerseNumber: showVerseNumber,
                style: numberStyle,
                isTagged: isTagged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerseNumberBadge extends StatelessWidget {
  const _VerseNumberBadge({
    required this.verse,
    required this.showVerseNumber,
    required this.style,
    required this.isTagged,
  });

  final int verse;
  final bool showVerseNumber;
  final TextStyle style;
  final bool isTagged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!showVerseNumber) {
      return const SizedBox.shrink();
    }
    if (!isTagged) {
      return Text(
        '$verse',
        style: style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          '$verse',
          style: style.copyWith(color: theme.colorScheme.onSurface),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }
}

double _measureTextWidth(
  String text,
  TextStyle style,
  TextDirection textDirection,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    maxLines: 1,
  )..layout();
  return painter.width;
}
