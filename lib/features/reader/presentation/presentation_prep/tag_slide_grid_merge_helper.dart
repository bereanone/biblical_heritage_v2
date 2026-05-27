import 'tag_slide_grid_models.dart';

class TagSlideGridMergeBounds {
  const TagSlideGridMergeBounds({
    required this.minRow,
    required this.maxRow,
    required this.minColumn,
    required this.maxColumn,
  });

  final int minRow;
  final int maxRow;
  final int minColumn;
  final int maxColumn;

  int get rowSpan => maxRow - minRow + 1;
  int get columnSpan => maxColumn - minColumn + 1;
  int get cellCount => rowSpan * columnSpan;
}

class TagSlideGridMergeHelper {
  const TagSlideGridMergeHelper._();

  static TagSlideGridMergeBounds? boundsForSelection(
    Set<TagPresentationGridCellCoordinate> selection,
  ) {
    if (selection.isEmpty) return null;
    var minRow = selection.first.row;
    var maxRow = selection.first.row;
    var minColumn = selection.first.column;
    var maxColumn = selection.first.column;
    for (final coordinate in selection) {
      if (coordinate.row < minRow) minRow = coordinate.row;
      if (coordinate.row > maxRow) maxRow = coordinate.row;
      if (coordinate.column < minColumn) minColumn = coordinate.column;
      if (coordinate.column > maxColumn) maxColumn = coordinate.column;
    }
    return TagSlideGridMergeBounds(
      minRow: minRow,
      maxRow: maxRow,
      minColumn: minColumn,
      maxColumn: maxColumn,
    );
  }

  static String? validateRectangularSelection(
    Set<TagPresentationGridCellCoordinate> selection,
  ) {
    if (selection.length < 2) {
      return 'Select at least 2 adjacent cells that form a rectangle.';
    }
    final bounds = boundsForSelection(selection);
    if (bounds == null) {
      return 'Select adjacent cells that form a rectangle.';
    }
    if (selection.length != bounds.cellCount) {
      return 'Select adjacent cells that form a rectangle.';
    }
    return null;
  }

  static TagPresentationMergedRegion createMergedRegion({
    required String id,
    required Set<TagPresentationGridCellCoordinate> selection,
    required List<String> itemIds,
  }) {
    final bounds = boundsForSelection(selection);
    if (bounds == null) {
      throw ArgumentError('Selection cannot be empty.');
    }
    return TagPresentationMergedRegion(
      id: id,
      startRow: bounds.minRow,
      startColumn: bounds.minColumn,
      rowSpan: bounds.rowSpan,
      columnSpan: bounds.columnSpan,
      itemIds: List<String>.from(itemIds),
    );
  }
}
