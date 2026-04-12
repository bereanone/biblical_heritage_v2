import 'package:flutter/material.dart';

import 'bible_explorer_screen.dart';
import '../data/highlights_repository.dart';
import 'highlight_render.dart';
import 'viewer_markup_span_builder.dart';
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
    this.isRangeSelected = false,
    required this.onTap,
    this.onLongPress,
  });

  final VerseLine line;
  final TextStyle style;
  final bool isSelected;
  final bool showChapterNumber;
  final bool startsInRedLetter;
  final bool isTagged;
  final VerseHighlightRecord? highlight;
  final bool isRangeSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
    final baseTextColor = highlightSpec?.textColor ?? theme.colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
          child: RichText(
            text: TextSpan(
              children: [
                if (showChapterNumber)
                  TextSpan(
                    text: '${line.chapter} ',
                    style: chapterStyle,
                  ),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Padding(
                    padding: EdgeInsets.only(right: isTagged ? 6 : 5),
                    child: _VerseNumberBadge(
                      verse: line.verse,
                      showVerseNumber: !showChapterNumber,
                      style: numberStyle,
                      isTagged: isTagged,
                    ),
                  ),
                ),
                buildViewerMarkupSpan(
                  html: line.html,
                  fallbackText: line.text,
                  baseStyle: style.copyWith(color: baseTextColor),
                  redLetterColor: redLetterColor,
                  startsInRedLetter: startsInRedLetter,
                ),
              ],
            ),
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
      return Text('$verse', style: style);
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
        ),
      ),
    );
  }
}
