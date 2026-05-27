import 'package:flutter/material.dart';

import '../../data/tags/unified_tag_models.dart';
import 'tag_presentation_prep_models.dart';
import 'tag_slide_grid_merge_helper.dart';
import 'tag_slide_grid_layout_helper.dart';
import 'tag_slide_grid_models.dart';

class TagPresentationPrepWorkspace {
  TagPresentationPrepWorkspace({
    required this.requestedTagName,
    required this.sourceSummary,
    required this.resolvedChains,
    required this.items,
    required this.slides,
    this.selectedSlideIndex = 0,
    this.selectedItemId,
    this.selectedCell,
    Set<TagPresentationGridCellCoordinate>? selectedMergeCells,
    this.mergeSelectionMode = false,
    this.mergeSelectionMessage,
  }) : itemsById = {for (final item in items) item.id: item},
       selectedMergeCells =
           selectedMergeCells ?? <TagPresentationGridCellCoordinate>{};

  factory TagPresentationPrepWorkspace.fromPreview(
    TagPresentationPrepPreview preview,
  ) {
    return TagPresentationPrepWorkspace(
      requestedTagName: preview.requestedTagName,
      sourceSummary: preview.sourceSummary,
      resolvedChains: List<UnifiedTagChain>.from(preview.resolvedChains),
      items: List<UnifiedTagChainItem>.from(preview.items),
      slides: preview.slides.map(_cloneSlide).toList(),
      selectedSlideIndex: 0,
      selectedItemId: null,
      selectedCell: null,
      selectedMergeCells: <TagPresentationGridCellCoordinate>{},
    );
  }

  final String requestedTagName;
  final String sourceSummary;
  final List<UnifiedTagChain> resolvedChains;
  final List<UnifiedTagChainItem> items;
  final Map<String, UnifiedTagChainItem> itemsById;
  final List<TagPresentationPrepSlide> slides;
  int selectedSlideIndex;
  String? selectedItemId;
  TagPresentationGridCellCoordinate? selectedCell;
  final Set<TagPresentationGridCellCoordinate> selectedMergeCells;
  bool mergeSelectionMode;
  String? mergeSelectionMessage;
  final Map<TagPresentationPrepSlide, TagPresentationLayoutPreset>
  _layoutPresetBySlide =
      <TagPresentationPrepSlide, TagPresentationLayoutPreset>{};

  bool get hasSlides => slides.isNotEmpty;

  TagPresentationPrepSlide? get selectedSlide {
    if (slides.isEmpty) return null;
    final index = selectedSlideIndex.clamp(0, slides.length - 1);
    return slides[index];
  }

  int get selectedGridRows => selectedSlide?.gridLayout.rows ?? 2;
  int get selectedGridColumns => selectedSlide?.gridLayout.columns ?? 2;
  double get selectedAspectRatio =>
      selectedSlide?.aspectRatio.aspectRatio ?? 16 / 9;
  TagPresentationAspectRatio get selectedAspectRatioSetting =>
      selectedSlide?.aspectRatio ??
      const TagPresentationAspectRatio.sixteenByNine();

  TagPresentationMergedRegion? get selectedMergedRegion {
    final slide = selectedSlide;
    final cell = selectedCell;
    if (slide == null || cell == null) return null;
    return slide.gridLayout.mergedRegionAt(cell.row, cell.column);
  }

  bool get hasSelectedZone => selectedCell != null;

  String? get selectedZoneId {
    final slide = selectedSlide;
    final cell = selectedCell;
    if (slide == null || cell == null) return null;
    final region = slide.gridLayout.mergedRegionAt(cell.row, cell.column);
    if (region != null) return 'merge:${region.id}';
    return 'cell:${cell.row}:${cell.column}';
  }

  String get selectedZoneLabel {
    final slide = selectedSlide;
    final cell = selectedCell;
    if (slide == null || cell == null) {
      return 'No zone selected';
    }
    final region = slide.gridLayout.mergedRegionAt(cell.row, cell.column);
    if (region != null) {
      return 'Merged zone ${region.rowSpan}x${region.columnSpan}';
    }
    return 'Cell ${cell.row + 1}, ${cell.column + 1}';
  }

  bool get canApplySelectedMerge {
    return TagSlideGridMergeHelper.validateRectangularSelection(
          selectedMergeCells,
        ) ==
        null;
  }

  TagPresentationLayoutPreset get selectedLayoutPreset {
    final slide = selectedSlide;
    if (slide == null) return TagPresentationLayoutPreset.fullWidth;
    return _layoutPresetBySlide[slide] ?? TagPresentationLayoutPreset.fullWidth;
  }

  void setSelectedLayoutPreset(TagPresentationLayoutPreset preset) {
    final slide = selectedSlide;
    if (slide == null) return;
    _layoutPresetBySlide[slide] = preset;
  }

  TagPresentationLayoutPreset layoutPresetForSlide(
    TagPresentationPrepSlide slide,
  ) {
    return _layoutPresetBySlide[slide] ?? TagPresentationLayoutPreset.fullWidth;
  }

  void setSelectedGridRows(int rows) {
    setSelectedGridSize(rows: rows, columns: selectedGridColumns);
  }

  void setSelectedGridColumns(int columns) {
    setSelectedGridSize(rows: selectedGridRows, columns: columns);
  }

  void setSelectedGridSize({required int rows, required int columns}) {
    final slide = selectedSlide;
    if (slide == null) return;
    final safeRows = rows < 1 ? 1 : rows;
    final safeColumns = columns < 1 ? 1 : columns;
    slide.gridLayout = TagPresentationGridLayout.fromItemIds(
      rows: safeRows,
      columns: safeColumns,
      itemIds: slide.assignedItemIds,
    );
    selectedCell = _firstOccupiedCellCoordinate(slide);
    selectedMergeCells.clear();
    mergeSelectionMode = false;
    mergeSelectionMessage = null;
    _renumberSlides();
  }

  UnifiedTagChainItem? itemById(String itemId) => itemsById[itemId];

  bool isItemPlaced(String itemId) {
    return _itemLocation(itemId) != null;
  }

  List<UnifiedTagChainItem> get unassignedItems {
    final placedIds = <String>{};
    for (final slide in slides) {
      for (final id in slide.gridLayout.assignedItemIds) {
        placedIds.add(id);
      }
      for (final cell in slide.sortedCells) {
        if (slide.gridLayout.isCellCoveredByMergedRegion(
          cell.row,
          cell.column,
        )) {
          continue;
        }
        placedIds.addAll(cell.itemIds);
      }
    }
    return [
      for (final item in items)
        if (!placedIds.contains(item.id)) item,
    ];
  }

  List<UnifiedTagChainItem> selectedSlideItems() {
    final slide = selectedSlide;
    if (slide == null) return const <UnifiedTagChainItem>[];
    final resolved = <UnifiedTagChainItem>[];
    for (final region in slide.gridLayout.sortedMergedRegions) {
      for (final itemId in region.itemIds) {
        final item = itemsById[itemId];
        if (item != null) resolved.add(item);
      }
    }
    for (final cell in slide.sortedCells) {
      if (slide.gridLayout.isCellCoveredByMergedRegion(cell.row, cell.column)) {
        continue;
      }
      for (final itemId in cell.itemIds) {
        final item = itemsById[itemId];
        if (item != null) resolved.add(item);
      }
    }
    return resolved;
  }

  List<UnifiedTagChainItem> selectedSlideCards() {
    return selectedSlideItems();
  }

  List<TagPresentationGridCell> selectedSlideCells() {
    final slide = selectedSlide;
    if (slide == null) return const <TagPresentationGridCell>[];
    return slide.gridLayout.visibleCells;
  }

  int? slideNumberForItem(String itemId) {
    final location = _itemLocation(itemId);
    return location == null ? null : slides[location.slideIndex].slideNumber;
  }

  TagPresentationGridCellCoordinate? cellForItem(String itemId) {
    final location = _itemLocation(itemId);
    return location?.cell;
  }

  bool hasPlacedCards(TagPresentationPrepSlide slide) {
    return slide.gridLayout.isEmpty == false;
  }

  void selectSlide(int index) {
    if (slides.isEmpty) {
      selectedSlideIndex = 0;
      selectedItemId = null;
      selectedCell = null;
      return;
    }
    selectedSlideIndex = index.clamp(0, slides.length - 1);
    final slide = slides[selectedSlideIndex];
    final firstItem = _firstItemInSlide(slide);
    selectedItemId = firstItem?.itemId;
    selectedCell = firstItem?.cell;
    selectedMergeCells.clear();
    mergeSelectionMode = false;
    mergeSelectionMessage = null;
  }

  void selectItem(String itemId) {
    final location = _itemLocation(itemId);
    selectedItemId = itemId;
    if (location == null) return;
    selectedSlideIndex = location.slideIndex;
    selectedCell = location.cell;
  }

  void selectCell(int row, int column) {
    final slide = selectedSlide;
    if (slide == null) return;
    final cell = slide.gridLayout.cellAt(row, column);
    if (cell == null) return;
    final coordinate = TagPresentationGridCellCoordinate(
      row: row,
      column: column,
    );
    final mergedRegion = slide.gridLayout.mergedRegionAt(row, column);
    if (mergeSelectionMode) {
      if (mergedRegion != null) {
        mergeSelectionMessage =
            'Unmerge the existing zone before selecting its cells.';
        return;
      }
      mergeSelectionMessage = null;
      if (selectedMergeCells.contains(coordinate)) {
        selectedMergeCells.remove(coordinate);
      } else {
        selectedMergeCells.add(coordinate);
      }
      selectedCell = coordinate;
      selectedItemId = cell.itemIds.isNotEmpty ? cell.itemIds.first : null;
      return;
    }

    selectedCell = mergedRegion?.anchor ?? coordinate;
    if (mergedRegion != null && mergedRegion.itemIds.isNotEmpty) {
      selectedItemId = mergedRegion.itemIds.first;
      return;
    }
    if (cell.itemIds.isNotEmpty) {
      selectedItemId = cell.itemIds.first;
    } else {
      selectedItemId = null;
    }
  }

  void clearCellSelection() {
    selectedCell = null;
  }

  void startMergeSelection() {
    mergeSelectionMode = true;
    mergeSelectionMessage = null;
    selectedMergeCells.clear();
  }

  void cancelMergeSelection() {
    mergeSelectionMode = false;
    mergeSelectionMessage = null;
    selectedMergeCells.clear();
  }

  void toggleMergeSelectionCell(int row, int column) {
    final slide = selectedSlide;
    if (slide == null) return;
    if (slide.gridLayout.isCellCoveredByMergedRegion(row, column)) {
      mergeSelectionMessage =
          'Unmerge the existing zone before selecting its cells.';
      return;
    }
    final cell = TagPresentationGridCellCoordinate(row: row, column: column);
    if (selectedMergeCells.contains(cell)) {
      selectedMergeCells.remove(cell);
    } else {
      selectedMergeCells.add(cell);
    }
    selectedCell = cell;
    final base = slide.gridLayout.cellAt(row, column);
    selectedItemId = base != null && base.itemIds.isNotEmpty
        ? base.itemIds.first
        : null;
    mergeSelectionMessage = selectedMergeCells.isEmpty
        ? null
        : TagSlideGridMergeHelper.validateRectangularSelection(
            selectedMergeCells,
          );
  }

  bool applySelectedMerge() {
    final slide = selectedSlide;
    if (slide == null) return false;
    final validation = TagSlideGridMergeHelper.validateRectangularSelection(
      selectedMergeCells,
    );
    if (validation != null) {
      mergeSelectionMessage = validation;
      return false;
    }
    final bounds = TagSlideGridMergeHelper.boundsForSelection(
      selectedMergeCells,
    );
    if (bounds == null) {
      mergeSelectionMessage = 'Select adjacent cells that form a rectangle.';
      return false;
    }

    final cells = _cloneCells(slide.gridLayout.cells);
    final mergedRegions = _cloneMergedRegions(slide.gridLayout.mergedRegions);
    final orderedSelection =
        [for (final coordinate in selectedMergeCells) coordinate]
          ..sort((left, right) {
            final rowCompare = left.row.compareTo(right.row);
            if (rowCompare != 0) return rowCompare;
            return left.column.compareTo(right.column);
          });

    final mergedItemIds = <String>[];
    for (final coordinate in orderedSelection) {
      final cellIndex = _cellIndex(slide.gridLayout, coordinate);
      if (cellIndex < 0) continue;
      final cell = cells[cellIndex];
      mergedItemIds.addAll(cell.itemIds);
      cells[cellIndex] = cell.copyWith(itemIds: const <String>[]);
    }

    final region = TagSlideGridMergeHelper.createMergedRegion(
      id: _nextMergeRegionId(slide),
      selection: selectedMergeCells,
      itemIds: mergedItemIds,
    );
    mergedRegions.add(region);
    slide.gridLayout = slide.gridLayout.copyWith(
      cells: cells,
      mergedRegions: mergedRegions,
    );
    mergeSelectionMode = false;
    mergeSelectionMessage = null;
    selectedMergeCells.clear();
    selectedCell = region.anchor;
    selectedItemId = region.itemIds.isNotEmpty ? region.itemIds.first : null;
    _renumberSlides();
    return true;
  }

  bool unmergeSelectedRegion() {
    final slide = selectedSlide;
    final cell = selectedCell;
    if (slide == null || cell == null) return false;
    final region = slide.gridLayout.mergedRegionAt(cell.row, cell.column);
    if (region == null) {
      mergeSelectionMessage = 'Select a merged zone to unmerge it.';
      return false;
    }
    final mergedRegions = _cloneMergedRegions(slide.gridLayout.mergedRegions)
      ..removeWhere((candidate) => candidate.id == region.id);
    slide.gridLayout = slide.gridLayout.copyWith(mergedRegions: mergedRegions);
    mergeSelectionMode = false;
    mergeSelectionMessage = 'Merged items returned to Unassigned Cards.';
    selectedMergeCells.clear();
    selectedItemId = null;
    selectedCell = region.anchor;
    _renumberSlides();
    return true;
  }

  void newBlankSlide() {
    final rows = selectedGridRows;
    final columns = selectedGridColumns;
    final insertIndex = slides.isEmpty
        ? 0
        : selectedSlideIndex.clamp(0, slides.length - 1) + 1;
    slides.insert(
      insertIndex,
      TagPresentationPrepSlide(
        slideNumber: insertIndex + 1,
        label: 'Slide ${insertIndex + 1}',
        gridLayout: TagPresentationGridLayout.empty(
          rows: rows,
          columns: columns,
        ),
        isDraft: true,
        aspectRatio: selectedAspectRatioSetting,
        topHeaderText: null,
        bottomFooterText: null,
      ),
    );
    _renumberSlides();
    selectSlide(insertIndex);
  }

  void duplicateSelectedSlide() {
    final slide = selectedSlide;
    if (slide == null) return;
    final insertIndex = selectedSlideIndex + 1;
    slides.insert(
      insertIndex,
      TagPresentationPrepSlide(
        slideNumber: insertIndex + 1,
        label: 'Slide ${insertIndex + 1}',
        gridLayout: _cloneLayout(slide.gridLayout),
        isDraft: slide.isBlank,
        sourcePresentationSlideNumber: slide.sourcePresentationSlideNumber,
        aspectRatio: slide.aspectRatio,
        topHeaderText: slide.topHeaderText,
        bottomFooterText: slide.bottomFooterText,
      ),
    );
    _renumberSlides();
    selectSlide(insertIndex);
  }

  bool placeItemOnSelectedSlide(
    String itemId,
    Offset normalizedCenter, {
    required double normalizedWidth,
    required double normalizedHeight,
    required bool avoidOverlap,
  }) {
    final slide = selectedSlide;
    if (slide == null) return false;
    final item = itemsById[itemId];
    if (item == null) return false;

    final helper = TagSlideGridLayoutHelper(
      rows: slide.gridLayout.rows,
      columns: slide.gridLayout.columns,
    );
    final requestedCell = helper.cellForPoint(normalizedCenter);
    final targetRegion = slide.gridLayout.mergedRegionAt(
      requestedCell.row,
      requestedCell.column,
    );
    final location = _itemLocation(itemId);
    final existingLocation = location?.cell;
    final shouldAvoidOverlap =
        avoidOverlap &&
        (location == null || location.slideIndex != selectedSlideIndex);
    final targetCell = targetRegion != null
        ? requestedCell
        : shouldAvoidOverlap
        ? helper.findOpenCell(
                requestedCell: requestedCell,
                occupiedCells: _occupiedCoordinatesForSlide(
                  slide,
                  excludingItemId: itemId,
                ),
              ) ??
              requestedCell
        : requestedCell;

    if (location != null) {
      _removeItemAtLocation(location);
    }

    _addItemToSelectedSlide(itemId, targetCell);
    selectedItemId = itemId;
    selectedCell = targetRegion?.anchor ?? targetCell;
    if (existingLocation != null && existingLocation == targetCell) {
      selectedCell = existingLocation;
    }
    _renumberSlides();
    return true;
  }

  bool assignItemToSelectedZone(String itemId) {
    final slide = selectedSlide;
    final cell = selectedCell;
    if (slide == null || cell == null) return false;
    final item = itemsById[itemId];
    if (item == null) return false;

    final location = _itemLocation(itemId);
    if (location != null) {
      _removeItemAtLocation(location);
    }

    final region = slide.gridLayout.mergedRegionAt(cell.row, cell.column);
    if (region != null) {
      final mergedRegions = _cloneMergedRegions(slide.gridLayout.mergedRegions);
      final regionIndex = mergedRegions.indexWhere(
        (candidate) => candidate.id == region.id,
      );
      if (regionIndex < 0) return false;
      final current = mergedRegions[regionIndex];
      final updatedIds = [
        for (final existingItemId in current.itemIds)
          if (existingItemId != itemId) existingItemId,
        itemId,
      ];
      mergedRegions[regionIndex] = TagPresentationMergedRegion(
        id: current.id,
        startRow: current.startRow,
        startColumn: current.startColumn,
        rowSpan: current.rowSpan,
        columnSpan: current.columnSpan,
        itemIds: updatedIds,
      );
      slide.gridLayout = slide.gridLayout.copyWith(
        mergedRegions: mergedRegions,
      );
      selectedItemId = itemId;
      selectedCell = region.anchor;
      _renumberSlides();
      return true;
    }

    final cells = _cloneCells(slide.gridLayout.cells);
    final cellIndex = _cellIndex(slide.gridLayout, cell);
    if (cellIndex < 0) return false;
    final current = cells[cellIndex];
    final updatedIds = [
      for (final existingItemId in current.itemIds)
        if (existingItemId != itemId) existingItemId,
      itemId,
    ];
    cells[cellIndex] = current.copyWith(itemIds: updatedIds);
    slide.gridLayout = slide.gridLayout.copyWith(cells: cells);
    selectedItemId = itemId;
    selectedCell = cell;
    _renumberSlides();
    return true;
  }

  bool setTopTitleForSelectedSlide(String title) {
    final slide = selectedSlide;
    final cleaned = title.trim();
    if (slide == null) return false;
    slide.topHeaderText = cleaned.isEmpty ? null : cleaned;
    _renumberSlides();
    return true;
  }

  bool setBottomTitleForSelectedSlide(String title) {
    final slide = selectedSlide;
    final cleaned = title.trim();
    if (slide == null) return false;
    slide.bottomFooterText = cleaned.isEmpty ? null : cleaned;
    _renumberSlides();
    return true;
  }

  bool setSelectedAspectRatio(TagPresentationAspectRatio aspectRatio) {
    final slide = selectedSlide;
    if (slide == null) return false;
    slide.aspectRatio = aspectRatio;
    _renumberSlides();
    return true;
  }

  bool moveItemWithinSelectedSlide(
    String itemId,
    Offset normalizedCenter, {
    required double normalizedWidth,
    required double normalizedHeight,
    bool avoidOverlap = false,
  }) {
    return placeItemOnSelectedSlide(
      itemId,
      normalizedCenter,
      normalizedWidth: normalizedWidth,
      normalizedHeight: normalizedHeight,
      avoidOverlap: avoidOverlap,
    );
  }

  bool removeItemFromSelectedSlide(String itemId) {
    final location = _itemLocation(itemId);
    if (location == null || location.slideIndex != selectedSlideIndex) {
      return false;
    }
    _removeItemAtLocation(location);
    final selectedSlide = slides[selectedSlideIndex];
    if (selectedItemId == itemId) {
      final first = _firstItemInSlide(selectedSlide);
      selectedItemId = first?.itemId;
      selectedCell = first?.cell;
    }
    _renumberSlides();
    return true;
  }

  TagPresentationPrepPreview snapshot() {
    return TagPresentationPrepPreview(
      requestedTagName: requestedTagName,
      sourceSummary: sourceSummary,
      resolvedChains: List<UnifiedTagChain>.unmodifiable(resolvedChains),
      items: List<UnifiedTagChainItem>.unmodifiable(items),
      slides: List<TagPresentationPrepSlide>.unmodifiable(
        slides.map(_cloneSlide).toList(growable: false),
      ),
    );
  }

  _ItemLocation? _itemLocation(String itemId) {
    for (var slideIndex = 0; slideIndex < slides.length; slideIndex++) {
      final slide = slides[slideIndex];
      final mergedRegions = slide.gridLayout.sortedMergedRegions;
      for (
        var regionIndex = 0;
        regionIndex < mergedRegions.length;
        regionIndex++
      ) {
        final region = mergedRegions[regionIndex];
        final itemIndex = region.itemIds.indexOf(itemId);
        if (itemIndex >= 0) {
          return _ItemLocation(
            slideIndex: slideIndex,
            cell: TagPresentationGridCellCoordinate(
              row: region.startRow,
              column: region.startColumn,
            ),
            itemIndex: itemIndex,
            slide: slide,
            mergedRegionId: region.id,
          );
        }
      }
      for (final cell in slide.sortedCells) {
        final itemIndex = cell.itemIds.indexOf(itemId);
        if (itemIndex >= 0) {
          return _ItemLocation(
            slideIndex: slideIndex,
            cell: TagPresentationGridCellCoordinate(
              row: cell.row,
              column: cell.column,
            ),
            itemIndex: itemIndex,
            slide: slide,
            mergedRegionId: null,
          );
        }
      }
    }
    return null;
  }

  void _removeItemAtLocation(_ItemLocation location) {
    final slide = location.slide;
    if (location.mergedRegionId != null) {
      final mergedRegions = _cloneMergedRegions(slide.gridLayout.mergedRegions);
      final regionIndex = mergedRegions.indexWhere(
        (candidate) => candidate.id == location.mergedRegionId,
      );
      if (regionIndex < 0) return;
      final region = mergedRegions[regionIndex];
      final updatedIds = List<String>.from(region.itemIds)
        ..removeAt(location.itemIndex);
      mergedRegions[regionIndex] = TagPresentationMergedRegion(
        id: region.id,
        startRow: region.startRow,
        startColumn: region.startColumn,
        rowSpan: region.rowSpan,
        columnSpan: region.columnSpan,
        itemIds: updatedIds,
      );
      slide.gridLayout = slide.gridLayout.copyWith(
        mergedRegions: mergedRegions,
      );
      return;
    }
    final cells = _cloneCells(slide.gridLayout.cells);
    final cellIndex = _cellIndex(slide.gridLayout, location.cell);
    if (cellIndex < 0) return;
    final cell = cells[cellIndex];
    final updatedIds = List<String>.from(cell.itemIds)
      ..removeAt(location.itemIndex);
    cells[cellIndex] = cell.copyWith(itemIds: updatedIds);
    slide.gridLayout = slide.gridLayout.copyWith(cells: cells);
  }

  void _addItemToSelectedSlide(
    String itemId,
    TagPresentationGridCellCoordinate cellCoordinate,
  ) {
    final slide = selectedSlide;
    if (slide == null) return;
    final targetRegion = slide.gridLayout.mergedRegionAt(
      cellCoordinate.row,
      cellCoordinate.column,
    );
    if (targetRegion != null) {
      final updatedRegions = _cloneMergedRegions(
        slide.gridLayout.mergedRegions,
      );
      final regionIndex = updatedRegions.indexWhere(
        (candidate) => candidate.id == targetRegion.id,
      );
      if (regionIndex < 0) return;
      final region = updatedRegions[regionIndex];
      final updatedIds = [
        for (final existingItemId in region.itemIds)
          if (existingItemId != itemId) existingItemId,
        itemId,
      ];
      updatedRegions[regionIndex] = TagPresentationMergedRegion(
        id: region.id,
        startRow: region.startRow,
        startColumn: region.startColumn,
        rowSpan: region.rowSpan,
        columnSpan: region.columnSpan,
        itemIds: updatedIds,
      );
      slide.gridLayout = slide.gridLayout.copyWith(
        mergedRegions: updatedRegions,
      );
      return;
    }
    final cells = _cloneCells(slide.gridLayout.cells);
    final cellIndex = _cellIndex(slide.gridLayout, cellCoordinate);
    if (cellIndex < 0) return;
    final cell = cells[cellIndex];
    final updatedIds = [
      for (final existingItemId in cell.itemIds)
        if (existingItemId != itemId) existingItemId,
      itemId,
    ];
    cells[cellIndex] = cell.copyWith(itemIds: updatedIds);
    slide.gridLayout = slide.gridLayout.copyWith(cells: cells);
  }

  int _cellIndex(
    TagPresentationGridLayout layout,
    TagPresentationGridCellCoordinate cellCoordinate,
  ) {
    for (var index = 0; index < layout.cells.length; index++) {
      final cell = layout.cells[index];
      if (cell.row == cellCoordinate.row &&
          cell.column == cellCoordinate.column) {
        return index;
      }
    }
    return -1;
  }

  Set<TagPresentationGridCellCoordinate> _occupiedCoordinatesForSlide(
    TagPresentationPrepSlide slide, {
    required String? excludingItemId,
  }) {
    final occupied = <TagPresentationGridCellCoordinate>{};
    for (final region in slide.gridLayout.sortedMergedRegions) {
      if (region.itemIds.any((itemId) => itemId != excludingItemId)) {
        occupied.addAll(region.coordinates());
      }
    }
    for (final cell in slide.sortedCells) {
      if (slide.gridLayout.isCellCoveredByMergedRegion(cell.row, cell.column)) {
        continue;
      }
      if (cell.itemIds.any((itemId) => itemId != excludingItemId)) {
        occupied.add(
          TagPresentationGridCellCoordinate(row: cell.row, column: cell.column),
        );
      }
    }
    return occupied;
  }

  _CellItemLocation? _firstItemInSlide(TagPresentationPrepSlide slide) {
    for (final region in slide.gridLayout.sortedMergedRegions) {
      if (region.itemIds.isEmpty) continue;
      return _CellItemLocation(
        cell: TagPresentationGridCellCoordinate(
          row: region.startRow,
          column: region.startColumn,
        ),
        itemId: region.itemIds.first,
      );
    }
    for (final cell in slide.sortedCells) {
      if (slide.gridLayout.isCellCoveredByMergedRegion(cell.row, cell.column)) {
        continue;
      }
      if (cell.itemIds.isEmpty) continue;
      return _CellItemLocation(
        cell: TagPresentationGridCellCoordinate(
          row: cell.row,
          column: cell.column,
        ),
        itemId: cell.itemIds.first,
      );
    }
    return null;
  }

  TagPresentationGridCellCoordinate? _firstOccupiedCellCoordinate(
    TagPresentationPrepSlide slide,
  ) {
    return _firstItemInSlide(slide)?.cell;
  }

  void _renumberSlides() {
    for (var index = 0; index < slides.length; index++) {
      final slide = slides[index];
      slide.slideNumber = index + 1;
      slide.label = 'Slide ${slide.slideNumber}';
      slide.isDraft = slide.isBlank;
    }
    if (slides.isEmpty) {
      selectedSlideIndex = 0;
      selectedItemId = null;
      selectedCell = null;
      return;
    }
    selectedSlideIndex = selectedSlideIndex.clamp(0, slides.length - 1);
    final selectedSlide = slides[selectedSlideIndex];
    if (selectedItemId == null ||
        selectedSlide.cellForItem(selectedItemId!) == null) {
      final first = _firstItemInSlide(selectedSlide);
      selectedItemId = first?.itemId;
      selectedCell = first?.cell;
    } else {
      final cell = selectedSlide.cellForItem(selectedItemId!);
      selectedCell = cell == null
          ? null
          : TagPresentationGridCellCoordinate(
              row: cell.row,
              column: cell.column,
            );
    }
  }

  String _nextMergeRegionId(TagPresentationPrepSlide slide) {
    final existing = slide.gridLayout.sortedMergedRegions.length;
    return '${slide.slideNumber}-merge-${existing + 1}';
  }
}

class _ItemLocation {
  const _ItemLocation({
    required this.slideIndex,
    required this.cell,
    required this.itemIndex,
    required this.slide,
    required this.mergedRegionId,
  });

  final int slideIndex;
  final TagPresentationGridCellCoordinate cell;
  final int itemIndex;
  final TagPresentationPrepSlide slide;
  final String? mergedRegionId;
}

class _CellItemLocation {
  const _CellItemLocation({required this.cell, required this.itemId});

  final TagPresentationGridCellCoordinate cell;
  final String itemId;
}

List<TagPresentationPrepSlide> buildTagPresentationPrepSlides(
  List<UnifiedTagChainItem> orderedItems,
) {
  final rows = orderedItems.length <= 2 ? 1 : 2;
  final columns = orderedItems.length <= 1 ? 1 : 2;
  return [
    TagPresentationPrepSlide(
      slideNumber: 1,
      label: 'Slide 1',
      gridLayout: TagPresentationGridLayout.empty(rows: rows, columns: columns),
      isDraft: true,
      aspectRatio: const TagPresentationAspectRatio.sixteenByNine(),
      topHeaderText: null,
      bottomFooterText: null,
    ),
  ];
}

TagPresentationPrepSlide _cloneSlide(TagPresentationPrepSlide slide) {
  return TagPresentationPrepSlide(
    slideNumber: slide.slideNumber,
    label: slide.label,
    gridLayout: _cloneLayout(slide.gridLayout),
    isDraft: slide.isDraft,
    sourcePresentationSlideNumber: slide.sourcePresentationSlideNumber,
    aspectRatio: slide.aspectRatio,
    topHeaderText: slide.topHeaderText,
    bottomFooterText: slide.bottomFooterText,
  );
}

TagPresentationGridLayout _cloneLayout(TagPresentationGridLayout layout) {
  return TagPresentationGridLayout(
    rows: layout.rows,
    columns: layout.columns,
    cells: _cloneCells(layout.cells),
    mergedRegions: _cloneMergedRegions(layout.mergedRegions),
  );
}

List<TagPresentationGridCell> _cloneCells(List<TagPresentationGridCell> cells) {
  return [
    for (final cell in cells)
      TagPresentationGridCell(
        row: cell.row,
        column: cell.column,
        itemIds: List<String>.from(cell.itemIds),
      ),
  ];
}

List<TagPresentationMergedRegion> _cloneMergedRegions(
  List<TagPresentationMergedRegion> regions,
) {
  return [
    for (final region in regions)
      TagPresentationMergedRegion(
        id: region.id,
        startRow: region.startRow,
        startColumn: region.startColumn,
        rowSpan: region.rowSpan,
        columnSpan: region.columnSpan,
        itemIds: List<String>.from(region.itemIds),
      ),
  ];
}
