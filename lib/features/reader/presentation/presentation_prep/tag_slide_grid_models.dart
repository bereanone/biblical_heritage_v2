class TagPresentationGridCellCoordinate {
  const TagPresentationGridCellCoordinate({
    required this.row,
    required this.column,
  });

  final int row;
  final int column;

  @override
  bool operator ==(Object other) {
    return other is TagPresentationGridCellCoordinate &&
        other.row == row &&
        other.column == column;
  }

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => '($row,$column)';
}

class TagPresentationGridCell {
  const TagPresentationGridCell({
    required this.row,
    required this.column,
    this.itemIds = const <String>[],
  });

  final int row;
  final int column;
  final List<String> itemIds;

  bool get isEmpty => itemIds.isEmpty;
  int get itemCount => itemIds.length;

  TagPresentationGridCell copyWith({
    int? row,
    int? column,
    List<String>? itemIds,
  }) {
    return TagPresentationGridCell(
      row: row ?? this.row,
      column: column ?? this.column,
      itemIds: itemIds ?? this.itemIds,
    );
  }
}

class TagPresentationMergedRegion {
  const TagPresentationMergedRegion({
    required this.id,
    required this.startRow,
    required this.startColumn,
    required this.rowSpan,
    required this.columnSpan,
    this.itemIds = const <String>[],
  });

  final String id;
  final int startRow;
  final int startColumn;
  final int rowSpan;
  final int columnSpan;
  final List<String> itemIds;

  bool contains(int row, int column) {
    return row >= startRow &&
        row < startRow + rowSpan &&
        column >= startColumn &&
        column < startColumn + columnSpan;
  }

  bool get isSingleCell => rowSpan == 1 && columnSpan == 1;

  TagPresentationGridCellCoordinate get anchor =>
      TagPresentationGridCellCoordinate(row: startRow, column: startColumn);

  Iterable<TagPresentationGridCellCoordinate> coordinates() sync* {
    for (var row = startRow; row < startRow + rowSpan; row++) {
      for (
        var column = startColumn;
        column < startColumn + columnSpan;
        column++
      ) {
        yield TagPresentationGridCellCoordinate(row: row, column: column);
      }
    }
  }
}

class TagPresentationGridLayout {
  TagPresentationGridLayout({
    required this.rows,
    required this.columns,
    List<TagPresentationGridCell>? cells,
    List<TagPresentationMergedRegion>? mergedRegions,
  }) : cells = List<TagPresentationGridCell>.unmodifiable(
         cells ?? _buildEmptyCells(rows, columns),
       ),
       mergedRegions = List<TagPresentationMergedRegion>.unmodifiable(
         mergedRegions ?? const <TagPresentationMergedRegion>[],
       );

  final int rows;
  final int columns;
  final List<TagPresentationGridCell> cells;
  final List<TagPresentationMergedRegion> mergedRegions;

  factory TagPresentationGridLayout.empty({int rows = 2, int columns = 2}) {
    return TagPresentationGridLayout(rows: rows, columns: columns);
  }

  factory TagPresentationGridLayout.fromItemIds({
    required int rows,
    required int columns,
    required List<String> itemIds,
    List<TagPresentationMergedRegion>? mergedRegions,
  }) {
    final cellCount = rows * columns;
    final cells = <TagPresentationGridCell>[
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          TagPresentationGridCell(row: row, column: column),
    ];

    if (cellCount > 0) {
      for (var index = 0; index < itemIds.length; index++) {
        final cellIndex = index % cellCount;
        final cell = cells[cellIndex];
        cells[cellIndex] = cell.copyWith(
          itemIds: [...cell.itemIds, itemIds[index]],
        );
      }
    }

    return TagPresentationGridLayout(
      rows: rows,
      columns: columns,
      cells: cells,
      mergedRegions: mergedRegions,
    );
  }

  bool get isEmpty => itemCount == 0;

  int get itemCount => assignedItemIds.length;

  List<String> get assignedItemIds {
    final ids = <String>[];
    for (final region in sortedMergedRegions) {
      ids.addAll(region.itemIds);
    }
    for (final cell in sortedCells) {
      if (isCellCoveredByMergedRegion(cell.row, cell.column)) continue;
      ids.addAll(cell.itemIds);
    }
    return List<String>.unmodifiable(ids);
  }

  List<TagPresentationGridCell> get sortedCells {
    final sorted = List<TagPresentationGridCell>.from(cells);
    sorted.sort((left, right) {
      final rowCompare = left.row.compareTo(right.row);
      if (rowCompare != 0) return rowCompare;
      return left.column.compareTo(right.column);
    });
    return List<TagPresentationGridCell>.unmodifiable(sorted);
  }

  List<TagPresentationGridCell> get visibleCells {
    return [
      for (final cell in sortedCells)
        if (!isCellCoveredByMergedRegion(cell.row, cell.column)) cell,
    ];
  }

  List<TagPresentationMergedRegion> get sortedMergedRegions {
    final sorted = List<TagPresentationMergedRegion>.from(mergedRegions);
    sorted.sort((left, right) {
      final rowCompare = left.startRow.compareTo(right.startRow);
      if (rowCompare != 0) return rowCompare;
      final columnCompare = left.startColumn.compareTo(right.startColumn);
      if (columnCompare != 0) return columnCompare;
      return left.id.compareTo(right.id);
    });
    return List<TagPresentationMergedRegion>.unmodifiable(sorted);
  }

  TagPresentationGridCell? cellAt(int row, int column) {
    for (final cell in cells) {
      if (cell.row == row && cell.column == column) return cell;
    }
    return null;
  }

  TagPresentationGridCell? cellForItem(String itemId) {
    for (final region in mergedRegions) {
      if (region.itemIds.contains(itemId)) {
        return TagPresentationGridCell(
          row: region.startRow,
          column: region.startColumn,
          itemIds: List<String>.from(region.itemIds),
        );
      }
    }
    for (final cell in cells) {
      if (cell.itemIds.contains(itemId)) return cell;
    }
    return null;
  }

  TagPresentationMergedRegion? mergedRegionAt(int row, int column) {
    for (final region in mergedRegions) {
      if (region.contains(row, column)) return region;
    }
    return null;
  }

  TagPresentationMergedRegion? mergedRegionForItem(String itemId) {
    for (final region in mergedRegions) {
      if (region.itemIds.contains(itemId)) return region;
    }
    return null;
  }

  bool isCellCoveredByMergedRegion(int row, int column) {
    return mergedRegionAt(row, column) != null;
  }

  TagPresentationGridLayout copyWith({
    int? rows,
    int? columns,
    List<TagPresentationGridCell>? cells,
    List<TagPresentationMergedRegion>? mergedRegions,
  }) {
    return TagPresentationGridLayout(
      rows: rows ?? this.rows,
      columns: columns ?? this.columns,
      cells: cells ?? this.cells,
      mergedRegions: mergedRegions ?? this.mergedRegions,
    );
  }
}

List<TagPresentationGridCell> _buildEmptyCells(int rows, int columns) {
  final safeRows = rows < 1 ? 1 : rows;
  final safeColumns = columns < 1 ? 1 : columns;
  return [
    for (var row = 0; row < safeRows; row++)
      for (var column = 0; column < safeColumns; column++)
        TagPresentationGridCell(row: row, column: column),
  ];
}
