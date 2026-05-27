import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tag_slide_grid_models.dart';

class TagSlideGridLayoutHelper {
  const TagSlideGridLayoutHelper({required this.rows, required this.columns});

  final int rows;
  final int columns;

  int get safeRows => rows < 1 ? 1 : rows;
  int get safeColumns => columns < 1 ? 1 : columns;

  double get cellWidth => 1.0 / safeColumns;
  double get cellHeight => 1.0 / safeRows;

  Rect rectForCell(int row, int column) {
    final safeRow = row.clamp(0, safeRows - 1).toInt();
    final safeColumn = column.clamp(0, safeColumns - 1).toInt();
    return Rect.fromLTWH(
      safeColumn * cellWidth,
      safeRow * cellHeight,
      cellWidth,
      cellHeight,
    );
  }

  Offset centerForCell(int row, int column) {
    final rect = rectForCell(row, column);
    return rect.center;
  }

  TagPresentationGridCellCoordinate cellForPoint(Offset normalizedPoint) {
    final column = (normalizedPoint.dx / cellWidth)
        .floor()
        .clamp(0, safeColumns - 1)
        .toInt();
    final row = (normalizedPoint.dy / cellHeight)
        .floor()
        .clamp(0, safeRows - 1)
        .toInt();
    return TagPresentationGridCellCoordinate(row: row, column: column);
  }

  TagPresentationGridCellCoordinate? findOpenCell({
    required TagPresentationGridCellCoordinate requestedCell,
    required Set<TagPresentationGridCellCoordinate> occupiedCells,
  }) {
    if (!occupiedCells.contains(requestedCell)) return requestedCell;

    final candidates = <TagPresentationGridCellCoordinate>[
      ..._candidateCells(requestedCell),
    ];
    for (final candidate in candidates) {
      if (_isInside(candidate) && !occupiedCells.contains(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  Iterable<TagPresentationGridCellCoordinate> _candidateCells(
    TagPresentationGridCellCoordinate base,
  ) sync* {
    for (var radius = 1; radius <= (safeRows + safeColumns); radius++) {
      yield TagPresentationGridCellCoordinate(
        row: base.row,
        column: base.column + radius,
      );
      yield TagPresentationGridCellCoordinate(
        row: base.row + radius,
        column: base.column,
      );
      yield TagPresentationGridCellCoordinate(
        row: base.row + radius,
        column: base.column + radius,
      );
      yield TagPresentationGridCellCoordinate(
        row: base.row + radius,
        column: base.column - radius,
      );
      yield TagPresentationGridCellCoordinate(
        row: base.row,
        column: base.column - radius,
      );
      yield TagPresentationGridCellCoordinate(
        row: base.row - radius,
        column: base.column,
      );
      yield TagPresentationGridCellCoordinate(
        row: base.row - radius,
        column: base.column + radius,
      );
      yield TagPresentationGridCellCoordinate(
        row: base.row - radius,
        column: base.column - radius,
      );
    }
  }

  bool _isInside(TagPresentationGridCellCoordinate coordinate) {
    return coordinate.row >= 0 &&
        coordinate.row < safeRows &&
        coordinate.column >= 0 &&
        coordinate.column < safeColumns;
  }
}

class TagPresentationSlideFrameLayout {
  const TagPresentationSlideFrameLayout({
    required this.slideSize,
    required this.topBandHeight,
    required this.bottomBandHeight,
  });

  final Size slideSize;
  final double topBandHeight;
  final double bottomBandHeight;

  Rect get slideRect => Offset.zero & slideSize;

  Rect get headerRect {
    if (topBandHeight <= 0) return Rect.zero;
    return Rect.fromLTWH(0, 0, slideSize.width, topBandHeight);
  }

  Rect get footerRect {
    if (bottomBandHeight <= 0) return Rect.zero;
    return Rect.fromLTWH(
      0,
      math.max(0.0, slideSize.height - bottomBandHeight),
      slideSize.width,
      bottomBandHeight,
    );
  }

  Rect get gridBodyRect {
    final top = topBandHeight.clamp(0.0, slideSize.height);
    final bottom = bottomBandHeight.clamp(0.0, slideSize.height);
    final height = math.max(0.0, slideSize.height - top - bottom);
    return Rect.fromLTWH(0, top, slideSize.width, height);
  }

  Size get gridBodySize => gridBodyRect.size;

  TagSlideGridLayoutHelper gridHelper({
    required int rows,
    required int columns,
  }) {
    return TagSlideGridLayoutHelper(rows: rows, columns: columns);
  }

  Rect cellRect({
    required TagSlideGridLayoutHelper helper,
    required int row,
    required int column,
  }) {
    final normalized = helper.rectForCell(row, column);
    return Rect.fromLTWH(
      normalized.left * gridBodyRect.width,
      normalized.top * gridBodyRect.height,
      normalized.width * gridBodyRect.width,
      normalized.height * gridBodyRect.height,
    );
  }

  Rect regionRect({
    required TagSlideGridLayoutHelper helper,
    required TagPresentationMergedRegion region,
  }) {
    final normalized = helper.rectForCell(region.startRow, region.startColumn);
    final cellWidth = gridBodyRect.width / helper.columns;
    final cellHeight = gridBodyRect.height / helper.rows;
    return Rect.fromLTWH(
      normalized.left * gridBodyRect.width,
      normalized.top * gridBodyRect.height,
      cellWidth * region.columnSpan,
      cellHeight * region.rowSpan,
    );
  }

  static double bandHeight(double availableHeight, String text) {
    final length = text.trim().length;
    final fraction = length <= 24
        ? 0.07
        : length <= 60
        ? 0.085
        : 0.10;
    return (availableHeight * fraction).clamp(24.0, 44.0);
  }
}

class TagPresentationSlideLayoutScope extends InheritedWidget {
  const TagPresentationSlideLayoutScope({
    super.key,
    required this.layout,
    required super.child,
  });

  final TagPresentationSlideFrameLayout layout;

  static TagPresentationSlideFrameLayout? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TagPresentationSlideLayoutScope>()
        ?.layout;
  }

  static TagPresentationSlideFrameLayout of(BuildContext context) {
    final layout = maybeOf(context);
    assert(layout != null, 'TagPresentationSlideLayoutScope not found.');
    return layout!;
  }

  @override
  bool updateShouldNotify(covariant TagPresentationSlideLayoutScope oldWidget) {
    return oldWidget.layout.slideSize != layout.slideSize ||
        oldWidget.layout.topBandHeight != layout.topBandHeight ||
        oldWidget.layout.bottomBandHeight != layout.bottomBandHeight;
  }
}
