import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/tags/unified_tag_models.dart';
import 'tag_presentation_prep_empty_state.dart';
import 'tag_presentation_auto_fit_text.dart';
import 'tag_presentation_prep_models.dart';
import 'tag_presentation_prep_state.dart';
import 'tag_presentation_slide_frame.dart';
import 'tag_slide_grid_layout_helper.dart';
import 'tag_slide_grid_item_chip.dart';
import 'tag_slide_grid_models.dart';

class TagSlideGridCanvas extends StatelessWidget {
  const TagSlideGridCanvas({
    super.key,
    required this.workspace,
    required this.onCardSelected,
    required this.onCardDropped,
    required this.onRemoveCard,
    this.onWorkspaceChanged,
    this.onCellSelected,
    this.readOnly = false,
    this.mediaRootPath,
  });

  final TagPresentationPrepWorkspace workspace;
  final ValueChanged<String> onCardSelected;
  final void Function(
    String itemId,
    Offset normalizedCenter,
    double normalizedWidth,
    double normalizedHeight,
    bool avoidOverlap,
  )
  onCardDropped;
  final ValueChanged<String> onRemoveCard;
  final VoidCallback? onWorkspaceChanged;
  final ValueChanged<TagPresentationGridCellCoordinate>? onCellSelected;
  final bool readOnly;
  final String? mediaRootPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedSlide = workspace.selectedSlide;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Working Slide',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedSlide == null
                            ? 'Select or create a slide to start arranging cards.'
                            : '${selectedSlide.label} · ${selectedSlide.gridLayout.rows}x${selectedSlide.gridLayout.columns}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (selectedSlide != null)
                  _SlideBadge(
                    label:
                        '${selectedSlide.placedCardCount} item${selectedSlide.placedCardCount == 1 ? '' : 's'}',
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (selectedSlide == null) {
                  return const TagPresentationPrepEmptyState(
                    title: 'No working slide selected',
                    message:
                        'Choose a slide from the navigator or create a new blank slide.',
                    hint: 'The canvas will show the selected slide here.',
                  );
                }

                final helper = TagSlideGridLayoutHelper(
                  rows: selectedSlide.gridLayout.rows,
                  columns: selectedSlide.gridLayout.columns,
                );
                final selectedCell = workspace.selectedCell;
                final selectedRegion = workspace.selectedMergedRegion;
                final cells = selectedSlide.gridLayout.visibleCells;
                final mergedRegions =
                    selectedSlide.gridLayout.sortedMergedRegions;
                final canvasKey = GlobalKey();

                return DragTarget<TagPresentationCardDragData>(
                  onWillAcceptWithDetails: (_) => !readOnly,
                  onAcceptWithDetails: (details) {
                    final box =
                        canvasKey.currentContext?.findRenderObject()
                            as RenderBox?;
                    if (box == null) return;
                    final gridSize = box.size;
                    if (gridSize.width <= 0 || gridSize.height <= 0) return;
                    final local = box.globalToLocal(details.offset);
                    final normalized = Offset(
                      (local.dx / gridSize.width).clamp(0.0, 1.0).toDouble(),
                      (local.dy / gridSize.height).clamp(0.0, 1.0).toDouble(),
                    );
                    final item = workspace.itemById(details.data.itemId);
                    if (item == null) return;
                    final size = _cellApproximateCardSize(
                      item,
                      gridSize,
                      selectedSlide.gridLayout.rows,
                      selectedSlide.gridLayout.columns,
                    );
                    onCardDropped(
                      item.id,
                      normalized,
                      size.width / gridSize.width,
                      size.height / gridSize.height,
                      details.data.sourceSlideIndex == null ||
                          details.data.sourceSlideIndex !=
                              workspace.selectedSlideIndex,
                    );
                  },
                  builder: (_, candidateData, _) {
                    final highlight = candidateData.isNotEmpty && !readOnly;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: highlight
                            ? theme.colorScheme.primaryContainer.withValues(
                                alpha: 0.10,
                              )
                            : theme.colorScheme.surfaceContainerLowest,
                        border: Border.all(
                          color: highlight
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: highlight ? 1.6 : 1,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: TagPresentationSlideFrame(
                        topBand: _SlideBandEditor(
                          key: ValueKey('top-${selectedSlide.slideNumber}'),
                          value: selectedSlide.topHeaderText ?? '',
                          hintText: 'Top title/header',
                          onChanged: (value) {
                            if (workspace.setTopTitleForSelectedSlide(value)) {
                              onWorkspaceChanged?.call();
                            }
                          },
                        ),
                        topBandHeightOverride: 40.0,
                        bottomBand: _SlideBandEditor(
                          key: ValueKey('bottom-${selectedSlide.slideNumber}'),
                          value: selectedSlide.bottomFooterText ?? '',
                          hintText: 'Bottom title/footer',
                          onChanged: (value) {
                            if (workspace.setBottomTitleForSelectedSlide(
                              value,
                            )) {
                              onWorkspaceChanged?.call();
                            }
                          },
                        ),
                        bottomBandHeightOverride: 40.0,
                        body: Builder(
                          builder: (bodyCtx) {
                            final bodyLayout =
                                TagPresentationSlideLayoutScope.maybeOf(bodyCtx);
                            final gridSize = bodyLayout?.gridBodySize ??
                                Size(
                                  math.max(0.0, constraints.maxWidth),
                                  math.max(0.0, constraints.maxHeight),
                                );
                            return Stack(
                              key: canvasKey,
                              children: [
                                Positioned.fill(
                                  child: ExcludeSemantics(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter: _GridPainter(
                                          rows: selectedSlide.gridLayout.rows,
                                          columns:
                                              selectedSlide.gridLayout.columns,
                                          color:
                                              theme.colorScheme.outlineVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                ..._buildGridZones(
                                  workspace: workspace,
                                  helper: helper,
                                  layout: bodyLayout,
                                  canvasSize: gridSize,
                                  selectedCell: selectedCell,
                                  selectedRegion: selectedRegion,
                                  mergedRegions: mergedRegions,
                                  cells: cells,
                                  mediaRootPath: mediaRootPath,
                                  readOnly: readOnly,
                                  onCellSelected: onCellSelected,
                                  onCardSelected: onCardSelected,
                                  onRemoveCard: onRemoveCard,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GridCellView extends StatelessWidget {
  const _GridCellView({
    required this.workspace,
    required this.cell,
    required this.selected,
    required this.readOnly,
    required this.mediaRootPath,
    required this.showOverflowWarning,
    required this.layout,
    required this.onCellTap,
    required this.onCardSelected,
    required this.onRemoveCard,
  });

  final TagPresentationPrepWorkspace workspace;
  final TagPresentationGridCell cell;
  final bool selected;
  final bool readOnly;
  final String? mediaRootPath;
  final bool showOverflowWarning;
  final TagPresentationSlideFrameLayout? layout;
  final VoidCallback onCellTap;
  final ValueChanged<String> onCardSelected;
  final ValueChanged<String> onRemoveCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      for (final itemId in cell.itemIds)
        if (workspace.itemById(itemId) != null) workspace.itemById(itemId)!,
    ];
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.68);
    final fillColor = selected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
            ),
            child: InkWell(
              onTap: onCellTap,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'Drop here',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var index = 0;
                              index < items.length;
                              index++
                            ) ...[
                              TagSlideGridItemChip(
                                item: items[index],
                                mediaRootPath: mediaRootPath,
                                dragData: readOnly
                                    ? null
                                    : TagPresentationCardDragData(
                                        itemId: items[index].id,
                                        sourceSlideIndex:
                                            workspace.selectedSlideIndex,
                                      ),
                                selected:
                                    workspace.selectedItemId == items[index].id,
                                showRemoveButton: !readOnly,
                                longPressDrag: !readOnly,
                                onTap: () => onCardSelected(items[index].id),
                                onRemove: readOnly
                                    ? null
                                    : () => onRemoveCard(items[index].id),
                              ),
                              if (index < items.length - 1)
                                const SizedBox(height: 6),
                            ],
                          ],
                        ),
                      ),
              ),
            ),
          ),
          if (showOverflowWarning)
            const Positioned(
              top: 4,
              right: 4,
              child: IgnorePointer(
                child: ExcludeSemantics(child: _OverflowWarningBadge()),
              ),
            ),
        ],
      ),
    );
  }
}

class _MergedRegionView extends StatelessWidget {
  const _MergedRegionView({
    required this.workspace,
    required this.region,
    required this.selected,
    required this.mergeSelectionMode,
    required this.selectedMergeCells,
    required this.readOnly,
    required this.mediaRootPath,
    required this.showOverflowWarning,
    required this.layout,
    required this.onTap,
    required this.onCardSelected,
    required this.onRemoveCard,
  });

  final TagPresentationPrepWorkspace workspace;
  final TagPresentationMergedRegion region;
  final bool selected;
  final bool mergeSelectionMode;
  final Set<TagPresentationGridCellCoordinate> selectedMergeCells;
  final bool readOnly;
  final String? mediaRootPath;
  final bool showOverflowWarning;
  final TagPresentationSlideFrameLayout? layout;
  final VoidCallback onTap;
  final ValueChanged<String> onCardSelected;
  final ValueChanged<String> onRemoveCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      for (final itemId in region.itemIds)
        if (workspace.itemById(itemId) != null) workspace.itemById(itemId)!,
    ];
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.92);
    final fillColor = selected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.92)
        : theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.96);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: selected ? 1.7 : 1.1,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Merged zone',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                            ),
                          ),
                        ),
                        Text(
                          '${region.rowSpan}x${region.columnSpan}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    if (mergeSelectionMode) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Tap cells to merge adjacent rectangles.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${selectedMergeCells.length} cell${selectedMergeCells.length == 1 ? '' : 's'} selected',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    if (items.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            'Drop here',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (
                                var index = 0;
                                index < items.length;
                                index++
                              ) ...[
                                TagSlideGridItemChip(
                                  item: items[index],
                                  mediaRootPath: mediaRootPath,
                                  dragData: readOnly
                                      ? null
                                      : TagPresentationCardDragData(
                                          itemId: items[index].id,
                                          sourceSlideIndex:
                                              workspace.selectedSlideIndex,
                                        ),
                                  selected:
                                      workspace.selectedItemId ==
                                      items[index].id,
                                  showRemoveButton: !readOnly,
                                  longPressDrag: !readOnly,
                                  onTap: () => onCardSelected(items[index].id),
                                  onRemove: readOnly
                                      ? null
                                      : () => onRemoveCard(items[index].id),
                                ),
                                if (index < items.length - 1)
                                  const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (showOverflowWarning)
            const Positioned(
              top: 4,
              right: 4,
              child: IgnorePointer(
                child: ExcludeSemantics(child: _OverflowWarningBadge()),
              ),
            ),
        ],
      ),
    );
  }
}

Rect _regionRect(
  TagSlideGridLayoutHelper helper,
  TagPresentationMergedRegion region,
  Size canvasSize,
) {
  final topLeft = helper.rectForCell(region.startRow, region.startColumn);
  final cellWidth = canvasSize.width / helper.columns;
  final cellHeight = canvasSize.height / helper.rows;
  return Rect.fromLTWH(
    topLeft.left * canvasSize.width,
    topLeft.top * canvasSize.height,
    cellWidth * region.columnSpan,
    cellHeight * region.rowSpan,
  );
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

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.rows,
    required this.columns,
    required this.color,
  });

  final int rows;
  final int columns;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    final rowHeight = size.height / rows;
    final columnWidth = size.width / columns;

    for (var column = 1; column < columns; column++) {
      final dx = column * columnWidth;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
    }
    for (var row = 1; row < rows; row++) {
      final dy = row * rowHeight;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.rows != rows ||
        oldDelegate.columns != columns ||
        oldDelegate.color != color;
  }
}

class _SlideBandEditor extends StatelessWidget {
  const _SlideBandEditor({
    super.key,
    required this.value,
    required this.hintText,
    required this.onChanged,
  });

  final String value;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SizedBox(
        height: 32,
        child: TextFormField(
          initialValue: value,
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          textInputAction: TextInputAction.done,
          onChanged: onChanged,
          maxLines: 1,
          decoration: InputDecoration(
            hintText: hintText,
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SlideBadge extends StatelessWidget {
  const _SlideBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

List<Widget> _buildGridZones({
  required TagPresentationPrepWorkspace workspace,
  required TagSlideGridLayoutHelper helper,
  required TagPresentationSlideFrameLayout? layout,
  required Size canvasSize,
  required TagPresentationGridCellCoordinate? selectedCell,
  required TagPresentationMergedRegion? selectedRegion,
  required List<TagPresentationMergedRegion> mergedRegions,
  required List<TagPresentationGridCell> cells,
  required String? mediaRootPath,
  required bool readOnly,
  required ValueChanged<TagPresentationGridCellCoordinate>? onCellSelected,
  required ValueChanged<String> onCardSelected,
  required ValueChanged<String> onRemoveCard,
}) {
  final widgets = <Widget>[];
  for (final region in mergedRegions) {
    widgets.add(
      Positioned.fromRect(
        rect:
            layout?.regionRect(helper: helper, region: region) ??
            _regionRect(helper, region, canvasSize),
        child: _MergedRegionView(
          workspace: workspace,
          region: region,
          selected:
              selectedRegion?.id == region.id ||
              (workspace.mergeSelectionMode &&
                  selectedCell != null &&
                  region.contains(selectedCell.row, selectedCell.column)),
          mergeSelectionMode: workspace.mergeSelectionMode,
          selectedMergeCells: workspace.selectedMergeCells,
          readOnly: readOnly,
          mediaRootPath: mediaRootPath,
          showOverflowWarning: _zoneNeedsOverflowWarning(
            items: [
              for (final itemId in region.itemIds)
                if (workspace.itemById(itemId) != null)
                  workspace.itemById(itemId)!,
            ],
            zoneSize: _regionRect(helper, region, canvasSize).size,
          ),
          layout: layout,
          onTap: () {
            if (readOnly) return;
            if (workspace.mergeSelectionMode) {
              onCellSelected?.call(
                TagPresentationGridCellCoordinate(
                  row: region.startRow,
                  column: region.startColumn,
                ),
              );
              return;
            }
            onCellSelected?.call(region.anchor);
          },
          onCardSelected: onCardSelected,
          onRemoveCard: onRemoveCard,
        ),
      ),
    );
  }

  for (final cell in cells) {
    widgets.add(
      Positioned.fromRect(
        rect:
            layout?.cellRect(
              helper: helper,
              row: cell.row,
              column: cell.column,
            ) ??
            _cellRect(helper, cell.row, cell.column, canvasSize),
        child: _GridCellView(
          workspace: workspace,
          cell: cell,
          selected: workspace.mergeSelectionMode
              ? workspace.selectedMergeCells.contains(
                  TagPresentationGridCellCoordinate(
                    row: cell.row,
                    column: cell.column,
                  ),
                )
              : selectedCell?.row == cell.row &&
                    selectedCell?.column == cell.column,
          readOnly: readOnly,
          mediaRootPath: mediaRootPath,
          showOverflowWarning: _zoneNeedsOverflowWarning(
            items: [
              for (final itemId in cell.itemIds)
                if (workspace.itemById(itemId) != null)
                  workspace.itemById(itemId)!,
            ],
            zoneSize: _cellRect(helper, cell.row, cell.column, canvasSize).size,
          ),
          layout: layout,
          onCellTap: () {
            if (readOnly) return;
            onCellSelected?.call(
              TagPresentationGridCellCoordinate(
                row: cell.row,
                column: cell.column,
              ),
            );
          },
          onCardSelected: onCardSelected,
          onRemoveCard: onRemoveCard,
        ),
      ),
    );
  }
  return widgets;
}

bool _zoneNeedsOverflowWarning({
  required List<UnifiedTagChainItem> items,
  required Size zoneSize,
}) {
  final text = _zoneWarningText(items);
  if (text == null) return false;

  final headingOnly =
      items.isNotEmpty &&
      items.every(
        (item) =>
            item.itemType == UnifiedTagItemType.heading ||
            item.isPresentationTitle,
      );

  final fit = measurePresentationTextFit(
    text: text,
    style: const TextStyle(
      color: Colors.transparent,
      fontSize: 14,
      height: 1.18,
    ),
    maxWidth: math.max(0.0, zoneSize.width - 16),
    maxHeight: math.max(0.0, zoneSize.height - 16),
    minFontSize: headingOnly ? 12.0 : 14.0,
    maxFontSize: headingOnly ? 30.0 : 26.0,
    maxLines: null,
    textAlign: TextAlign.left,
    height: 1.18,
    letterSpacing: null,
  );
  return !fit.fits;
}

String? _zoneWarningText(List<UnifiedTagChainItem> items) {
  final blocks = <String>[];
  for (final item in items) {
    final text = _warningTextForItem(item);
    if (text != null) {
      blocks.add(text);
    }
  }
  final cleaned = blocks.join('\n\n').trim();
  return cleaned.isEmpty ? null : cleaned;
}

String? _warningTextForItem(UnifiedTagChainItem item) {
  final title = item.displayTitle?.trim() ?? '';
  final body = item.textSnapshot?.trim() ?? '';
  final note = item.noteText?.trim() ?? '';
  final html = item.htmlContent?.trim() ?? '';

  return switch (item.itemType) {
    UnifiedTagItemType.heading => _firstNonEmpty([title, body, note, html]),
    UnifiedTagItemType.image || UnifiedTagItemType.media => _firstNonEmpty([
      item.media.isNotEmpty ? item.media.first.caption?.trim() ?? '' : '',
      title,
    ]),
    UnifiedTagItemType.note => _firstNonEmpty([note, body, title, html]),
    UnifiedTagItemType.eLibraryRange => _firstNonEmpty([
      body,
      note,
      title,
      html,
    ]),
    UnifiedTagItemType.bibleVerse ||
    UnifiedTagItemType.bibleRange ||
    UnifiedTagItemType.unknownLegacy => _firstNonEmpty([
      body,
      note,
      title,
      html,
    ]),
  };
}

String? _firstNonEmpty(List<String> values) {
  for (final value in values) {
    final cleaned = value.trim();
    if (cleaned.isNotEmpty) return cleaned;
  }
  return null;
}

Size _cellApproximateCardSize(
  UnifiedTagChainItem item,
  Size stageSize,
  int rows,
  int columns,
) {
  final cellWidth = stageSize.width / columns;
  final cellHeight = stageSize.height / rows;
  final widthFraction = switch (item.itemType) {
    UnifiedTagItemType.note => 0.92,
    UnifiedTagItemType.image || UnifiedTagItemType.media => 0.90,
    UnifiedTagItemType.heading => 0.88,
    UnifiedTagItemType.eLibraryRange => 0.92,
    UnifiedTagItemType.bibleRange => 0.92,
    UnifiedTagItemType.bibleVerse => 0.88,
    UnifiedTagItemType.unknownLegacy => 0.90,
  };
  final heightFraction = switch (item.itemType) {
    UnifiedTagItemType.note => 0.48,
    UnifiedTagItemType.image || UnifiedTagItemType.media => 0.50,
    UnifiedTagItemType.heading => 0.34,
    UnifiedTagItemType.eLibraryRange => 0.36,
    UnifiedTagItemType.bibleRange => 0.36,
    UnifiedTagItemType.bibleVerse => 0.32,
    UnifiedTagItemType.unknownLegacy => 0.36,
  };

  return Size(
    math.min(cellWidth * widthFraction, cellWidth * 0.96),
    math.min(cellHeight * heightFraction, cellHeight * 0.92),
  );
}

class _OverflowWarningBadge extends StatelessWidget {
  const _OverflowWarningBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFE0BE87).withValues(alpha: 0.42),
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.all(3),
        child: Icon(
          Icons.warning_amber_rounded,
          size: 14,
          color: Color(0xFFE0BE87),
        ),
      ),
    );
  }
}
