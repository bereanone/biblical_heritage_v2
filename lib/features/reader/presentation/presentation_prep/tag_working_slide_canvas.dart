import 'package:flutter/material.dart';

import 'tag_presentation_prep_state.dart';
import 'tag_slide_grid_canvas.dart';
import 'tag_slide_grid_models.dart';

class TagWorkingSlideCanvas extends StatelessWidget {
  const TagWorkingSlideCanvas({
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
    return TagSlideGridCanvas(
      workspace: workspace,
      onCardSelected: onCardSelected,
      onCardDropped: onCardDropped,
      onRemoveCard: onRemoveCard,
      onWorkspaceChanged: onWorkspaceChanged,
      onCellSelected: onCellSelected,
      readOnly: readOnly,
      mediaRootPath: mediaRootPath,
    );
  }
}
