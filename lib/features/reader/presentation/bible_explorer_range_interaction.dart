import 'viewer_range_selection.dart';

bool isTapInsideCurrentSelection(ViewerRangeSelection selection, int blockId) {
  if (blockId <= 0) return false;
  if (!selection.hasCompletedRange) return false;
  return selection.containsBlock(blockId);
}

bool shouldOpenRangeActionsOnTap(ViewerRangeSelection selection, int blockId) {
  return isTapInsideCurrentSelection(selection, blockId);
}
