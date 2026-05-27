import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tag_presentation_prep_models.dart';
import 'tag_presentation_slide_frame.dart';
import 'tag_slide_grid_layout_helper.dart';
import 'tag_slide_grid_models.dart';

class TagPresentationSlideViewport extends StatelessWidget {
  const TagPresentationSlideViewport({
    super.key,
    required this.aspectRatio,
    required this.child,
    this.padding = const EdgeInsets.all(6),
  });

  final double aspectRatio;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(
          0.0,
          constraints.maxWidth - padding.horizontal,
        );
        final availableHeight = math.max(
          0.0,
          constraints.maxHeight - padding.vertical,
        );
        final size = _fitAspectRatio(
          availableWidth,
          availableHeight,
          aspectRatio,
        );
        if (size.width <= 0 || size.height <= 0) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: padding,
          child: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class TagPreparedSlideRenderer extends StatelessWidget {
  const TagPreparedSlideRenderer({
    super.key,
    required this.slide,
    required this.itemWidgetsById,
    required this.aspectRatio,
  });

  final TagPresentationPrepSlide slide;
  final Map<String, Widget> itemWidgetsById;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final helper = TagSlideGridLayoutHelper(
      rows: slide.gridLayout.rows,
      columns: slide.gridLayout.columns,
    );

    return TagPresentationSlideViewport(
      aspectRatio: aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF292622), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.56),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: TagPresentationSlideFrame(
            topTitleText: slide.topHeaderText,
            bottomTitleText: slide.bottomFooterText,
            body: LayoutBuilder(
              builder: (context, constraints) {
                final slideLayout = TagPresentationSlideLayoutScope.maybeOf(
                  context,
                );
                final mergedRegions = slide.gridLayout.sortedMergedRegions;
                final visibleCells = slide.gridLayout.visibleCells;
                final canvasSize =
                    slideLayout?.gridBodySize ??
                    Size(
                      math.max(0.0, constraints.maxWidth),
                      math.max(0.0, constraints.maxHeight),
                    );
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    const Positioned.fill(
                      child: ExcludeSemantics(
                        child: IgnorePointer(
                          child: _PresentationSlideBackground(),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: ExcludeSemantics(
                        child: IgnorePointer(child: _PresentationSlideGlow()),
                      ),
                    ),
                    for (final region in mergedRegions)
                      Positioned.fromRect(
                        rect:
                            slideLayout?.regionRect(
                              helper: helper,
                              region: region,
                            ) ??
                            _regionRect(helper, region, canvasSize),
                        child: _PreparedSlideZone(
                          itemWidgets: [
                            for (final itemId in region.itemIds)
                              if (itemWidgetsById[itemId] != null)
                                itemWidgetsById[itemId]!,
                          ],
                        ),
                      ),
                    for (final cell in visibleCells)
                      Positioned.fromRect(
                        rect:
                            slideLayout?.cellRect(
                              helper: helper,
                              row: cell.row,
                              column: cell.column,
                            ) ??
                            _cellRect(
                              helper,
                              cell.row,
                              cell.column,
                              canvasSize,
                            ),
                        child: _PreparedSlideZone(
                          itemWidgets: [
                            for (final itemId in cell.itemIds)
                              if (itemWidgetsById[itemId] != null)
                                itemWidgetsById[itemId]!,
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PreparedSlideZone extends StatelessWidget {
  const _PreparedSlideZone({required this.itemWidgets});

  final List<Widget> itemWidgets;

  @override
  Widget build(BuildContext context) {
    if (itemWidgets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          for (var index = 0; index < itemWidgets.length; index++) ...[
            Expanded(child: itemWidgets[index]),
            if (index < itemWidgets.length - 1) const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }
}

class _PresentationSlideBackground extends StatelessWidget {
  const _PresentationSlideBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF18181C), Color(0xFF0F0F12), Color(0xFF09090B)],
          stops: [0.0, 0.58, 1.0],
        ),
      ),
    );
  }
}

class _PresentationSlideGlow extends StatelessWidget {
  const _PresentationSlideGlow();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.06, -0.14),
            radius: 1.12,
            colors: [Color(0x22F1D9A0), Colors.transparent],
            stops: [0.0, 0.72],
          ),
        ),
      ),
    );
  }
}

Size _fitAspectRatio(double maxWidth, double maxHeight, double aspectRatio) {
  if (maxWidth <= 0 || maxHeight <= 0) {
    return Size.zero;
  }
  if (!aspectRatio.isFinite || aspectRatio <= 0) {
    return Size(maxWidth, maxHeight);
  }

  var width = maxWidth;
  var height = width / aspectRatio;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * aspectRatio;
  }
  return Size(width, height);
}

Rect _cellRect(
  TagSlideGridLayoutHelper helper,
  int row,
  int column,
  Size canvasSize,
) {
  final normalized = helper.rectForCell(row, column);
  return Rect.fromLTWH(
    normalized.left * canvasSize.width,
    normalized.top * canvasSize.height,
    normalized.width * canvasSize.width,
    normalized.height * canvasSize.height,
  );
}

Rect _regionRect(
  TagSlideGridLayoutHelper helper,
  TagPresentationMergedRegion region,
  Size canvasSize,
) {
  final normalized = helper.rectForCell(region.startRow, region.startColumn);
  return Rect.fromLTWH(
    normalized.left * canvasSize.width,
    normalized.top * canvasSize.height,
    normalized.width * region.columnSpan * canvasSize.width,
    normalized.height * region.rowSpan * canvasSize.height,
  );
}
