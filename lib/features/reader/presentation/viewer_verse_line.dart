import 'package:flutter/material.dart';

import '../data/highlights_repository.dart';
import 'viewer_passage_models.dart';
import 'highlight_render.dart';
import 'viewer_markup_span_builder.dart';
import 'viewer_range_selection.dart';
import 'viewer_selection_style.dart';
import 'text_range_geometry.dart';

const bool _enableTextRangeGeometry = false;

class ViewerVerseLine extends StatelessWidget {
  const ViewerVerseLine({
    super.key,
    required this.line,
    required this.style,
    required this.isSelected,
    this.hasUserMarkup = false,
    this.showChapterNumber = false,
    this.startsInRedLetter = false,
    this.isTagged = false,
    this.highlight,
    this.tokenHighlights = const <VerseHighlightRecord>[],
    this.isRangeSelected = false,
    required this.onTap,
    this.onVerseNumberTap,
    this.onVerseNumberLongPress,
    this.onVerseNumberLongPressMoveDetails,
    this.rangeSelection,
    this.onTokenLongPress,
    this.onTokenLongPressMove,
    this.onTokenLongPressMoveDetails,
    this.geometryRegistry,
    this.geometryScopeId,
    this.geometryRevision = 0,
  });

  final VerseLine line;
  final TextStyle style;
  final bool isSelected;
  final bool hasUserMarkup;
  final bool showChapterNumber;
  final bool startsInRedLetter;
  final bool isTagged;
  final VerseHighlightRecord? highlight;
  final List<VerseHighlightRecord> tokenHighlights;
  final bool isRangeSelected;
  final VoidCallback onTap;
  final VoidCallback? onVerseNumberTap;
  final VoidCallback? onVerseNumberLongPress;
  final ValueChanged<LongPressMoveUpdateDetails>?
  onVerseNumberLongPressMoveDetails;
  final ViewerRangeSelection? rangeSelection;
  final ValueChanged<int>? onTokenLongPress;
  final ValueChanged<int>? onTokenLongPressMove;
  final ValueChanged<LongPressMoveUpdateDetails>? onTokenLongPressMoveDetails;
  final TextRangeGeometryRegistry? geometryRegistry;
  final String? geometryScopeId;
  final int geometryRevision;

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
      fontWeight: isSelected || isTagged || hasUserMarkup
          ? FontWeight.w700
          : FontWeight.w600,
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
            layerType: HighlightLayerType.savedVerse,
            readerBackground: theme.scaffoldBackgroundColor,
          );
    final baseTextColor =
        highlightSpec?.textColor ?? theme.colorScheme.onSurface;
    final rangeSelectionSpec = resolveHighlightRender(
      theme.colorScheme.primary,
      brightness == Brightness.dark,
      layerType: HighlightLayerType.temporarySelection,
      readerBackground: theme.scaffoldBackgroundColor,
    );
    final verseBackground = highlightSpec?.backgroundColor;
    final rangeSelectionBackground = isRangeSelected
        ? (rangeSelection?.hasTokenSelection == true
              ? verseBackground
              : Color.alphaBlend(
                  rangeSelectionSpec.backgroundColor,
                  verseBackground ?? Colors.transparent,
                ))
        : verseBackground;
    final geometrySeeds = <TextRangeLayoutSeed>[];
    final textSpan = TextSpan(
      children: [
        buildViewerMarkupSpan(
          html: line.html,
          fallbackText: line.text,
          baseStyle: style.copyWith(color: baseTextColor),
          redLetterColor: redLetterColor,
          isNightMode: brightness == Brightness.dark,
          startsInRedLetter: startsInRedLetter,
          blockId: line.blockId,
          rangeSelection: rangeSelection,
          onTokenLongPress: onTokenLongPress,
          onTokenLongPressMove: onTokenLongPressMove,
          onTokenLongPressMoveDetails: onTokenLongPressMoveDetails,
          persistedHighlights: tokenHighlights,
        ),
      ],
    );

    final registry = geometryRegistry;
    final textWidget = _enableTextRangeGeometry && registry != null
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPressStart: (details) {
              final anchor = _nearestAnchorForGlobalPosition(
                registry: registry,
                scopeId: geometryScopeId ?? 'viewer:${line.blockId ?? 0}',
                globalPosition: details.globalPosition,
              );
              if (anchor == null) return;
              onTokenLongPress?.call(anchor.tokenIndex);
            },
            onLongPressMoveUpdate: (details) {
              final anchor = _nearestAnchorForGlobalPosition(
                registry: registry,
                scopeId: geometryScopeId ?? 'viewer:${line.blockId ?? 0}',
                globalPosition: details.globalPosition,
              );
              if (anchor == null) return;
              onTokenLongPressMove?.call(anchor.tokenIndex);
            },
            child: TextRangeGeometryReporter(
              registry: registry,
              scopeId: geometryScopeId ?? 'viewer:${line.blockId ?? 0}',
              sourceKind: TextRangeSourceKind.bible,
              text: textSpan,
              seeds: geometrySeeds,
              geometryRevision: geometryRevision,
              textDirection: textDirection,
              textAlign: TextAlign.start,
              child: RichText(text: textSpan),
            ),
          )
        : RichText(text: textSpan);

    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 0 : 2,
          vertical: isSelected ? 0 : 1,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? viewerSelectedVerseColor(context)
              : rangeSelectionBackground ?? Colors.transparent,
          borderRadius: BorderRadius.circular(isSelected ? 3 : 6),
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
              numberStyle: highlightSpec == null
                  ? numberStyle
                  : numberStyle.copyWith(color: highlightSpec.textColor),
              isTagged: isTagged,
              textDirection: textDirection,
              onTap: onVerseNumberTap,
              onLongPress: onVerseNumberLongPress,
              onLongPressMoveDetails: onVerseNumberLongPressMoveDetails,
            ),
            Expanded(
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(isSelected ? 3 : 6),
                child: textWidget,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TextRangeAnchor? _nearestAnchorForGlobalPosition({
  required TextRangeGeometryRegistry registry,
  required String scopeId,
  required Offset globalPosition,
}) {
  return registry.nearestAnchorToGlobalPoint(
    globalPosition,
    sourceKind: TextRangeSourceKind.bible,
    scopeId: scopeId,
  );
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
    this.onTap,
    this.onLongPress,
    this.onLongPressMoveDetails,
  });

  final int chapter;
  final int verse;
  final bool showVerseNumber;
  final bool showChapterNumber;
  final TextStyle chapterStyle;
  final TextStyle numberStyle;
  final bool isTagged;
  final TextDirection textDirection;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<LongPressMoveUpdateDetails>? onLongPressMoveDetails;

  @override
  Widget build(BuildContext context) {
    final verseWidth = _measureTextWidth(
      context,
      '$verse',
      numberStyle,
      textDirection,
    ).ceilToDouble();
    // Reserve a 3-digit verse slot so chapters like Psalm 119 do not clip
    // once the verse numbers reach 100+ at larger font sizes.
    final reservedVerseWidth =
        _measureTextWidth(
          context,
          '888',
          numberStyle,
          textDirection,
        ).ceilToDouble() +
        4.0;
    final verseSlotWidth = verseWidth > reservedVerseWidth
        ? verseWidth
        : reservedVerseWidth;
    final chapterWidth = showChapterNumber
        ? _measureTextWidth(
            context,
            '$chapter',
            chapterStyle,
            textDirection,
          ).ceilToDouble()
        : 0.0;
    final badgePadding = isTagged ? 10.0 : 0.0;
    final contentWidth = showChapterNumber
        ? (chapterWidth > verseSlotWidth + badgePadding
              ? chapterWidth
              : verseSlotWidth + badgePadding)
        : verseSlotWidth + badgePadding;
    final width = contentWidth + 16.0;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressMoveUpdate: onLongPressMoveDetails,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width, minHeight: 48),
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
  BuildContext context,
  String text,
  TextStyle style,
  TextDirection textDirection,
) {
  final textScaler = MediaQuery.textScalerOf(context);
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    maxLines: 1,
    textScaler: textScaler,
  )..layout();
  return painter.width;
}
