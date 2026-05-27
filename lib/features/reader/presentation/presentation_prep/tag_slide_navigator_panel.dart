import 'package:flutter/material.dart';

import 'tag_presentation_prep_models.dart';
import 'tag_presentation_prep_state.dart';

class TagSlideNavigatorPanel extends StatefulWidget {
  const TagSlideNavigatorPanel({
    super.key,
    required this.workspace,
    required this.onNewBlankSlide,
    required this.onPreviewSlide,
    required this.onChooseCardPressed,
    required this.onAddTitlePressed,
    required this.onAspectRatioPresetChanged,
    required this.onEditCustomAspectRatio,
    required this.onRowsChanged,
    required this.onColumnsChanged,
    required this.onMergeCellsPressed,
    required this.onUnmergePressed,
    required this.onCancelMergePressed,
    required this.canApplyMerge,
  });

  final TagPresentationPrepWorkspace workspace;
  final VoidCallback onNewBlankSlide;
  final VoidCallback onPreviewSlide;
  final VoidCallback onChooseCardPressed;
  final VoidCallback onAddTitlePressed;
  final ValueChanged<TagPresentationAspectRatioPreset?>
  onAspectRatioPresetChanged;
  final VoidCallback onEditCustomAspectRatio;
  final ValueChanged<int> onRowsChanged;
  final ValueChanged<int> onColumnsChanged;
  final VoidCallback onMergeCellsPressed;
  final VoidCallback onUnmergePressed;
  final VoidCallback onCancelMergePressed;
  final bool canApplyMerge;

  @override
  State<TagSlideNavigatorPanel> createState() => _TagSlideNavigatorPanelState();
}

class _TagSlideNavigatorPanelState extends State<TagSlideNavigatorPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedSlide = widget.workspace.selectedSlide;
    final selectedSlideLabel = selectedSlide?.label ?? 'No slide selected';
    final rows = widget.workspace.selectedGridRows;
    final columns = widget.workspace.selectedGridColumns;
    final aspectRatio = widget.workspace.selectedAspectRatioSetting;
    final headerRow = Row(
      children: [
        Expanded(
          child: Text(
            'Slide Controls',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _SlideBadge(label: selectedSlideLabel),
      ],
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasBoundedHeight = constraints.maxHeight.isFinite;
            final body = _buildScrollableBody(
              context,
              workspace: widget.workspace,
              canPreview: selectedSlide != null,
              rows: rows,
              columns: columns,
              aspectRatio: aspectRatio,
            );

            if (!hasBoundedHeight) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  headerRow,
                  const SizedBox(height: 8),
                  body,
                ],
              );
            }

            return SizedBox(
              height: constraints.maxHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  headerRow,
                  const SizedBox(height: 8),
                  Expanded(
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: body,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildScrollableBody(
    BuildContext context, {
    required TagPresentationPrepWorkspace workspace,
    required bool canPreview,
    required int rows,
    required int columns,
    required TagPresentationAspectRatio aspectRatio,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Choose a slide, adjust the grid, open a blank slide, or preview the active canvas.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        _DropdownRow<TagPresentationAspectRatioPreset>(
          label: 'Display target',
          value: aspectRatio.preset,
          items: const [
            DropdownMenuItem(
              value: TagPresentationAspectRatioPreset.sixteenByNine,
              child: Text('16:9 Widescreen'),
            ),
            DropdownMenuItem(
              value: TagPresentationAspectRatioPreset.fourByThree,
              child: Text('4:3 Projector'),
            ),
            DropdownMenuItem(
              value: TagPresentationAspectRatioPreset.sixteenByTen,
              child: Text('16:10'),
            ),
            DropdownMenuItem(
              value: TagPresentationAspectRatioPreset.nineBySixteen,
              child: Text('9:16 Phone Portrait'),
            ),
            DropdownMenuItem(
              value: TagPresentationAspectRatioPreset.custom,
              child: Text('Custom'),
            ),
          ],
          onChanged: widget.onAspectRatioPresetChanged,
        ),
        if (aspectRatio.preset == TagPresentationAspectRatioPreset.custom) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: widget.onEditCustomAspectRatio,
              icon: const Icon(Icons.tune),
              label: Text(
                'Custom ${aspectRatio.customAspectRatio.toStringAsFixed(2)}:1',
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _DimensionStepper(
          label: 'Rows',
          value: rows,
          min: 1,
          max: 4,
          onDecrement: rows > 1 ? () => widget.onRowsChanged(rows - 1) : null,
          onIncrement: rows < 4 ? () => widget.onRowsChanged(rows + 1) : null,
        ),
        const SizedBox(height: 8),
        _DimensionStepper(
          label: 'Columns',
          value: columns,
          min: 1,
          max: 4,
          onDecrement: columns > 1
              ? () => widget.onColumnsChanged(columns - 1)
              : null,
          onIncrement: columns < 4
              ? () => widget.onColumnsChanged(columns + 1)
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          workspace.mergeSelectionMode
              ? 'Select adjacent cells that form a rectangle.'
              : 'Tap a cell to select it. Merge zones can be created from adjacent cells.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (workspace.hasSelectedZone) ...[
          FilledButton.tonalIcon(
            onPressed: widget.onChooseCardPressed,
            icon: const Icon(Icons.playlist_add_outlined),
            label: const Text('Choose Card'),
          ),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            onPressed: widget.onAddTitlePressed,
            icon: const Icon(Icons.title_outlined),
            label: const Text('Header / Footer'),
          ),
          const SizedBox(height: 6),
          Text(
            workspace.selectedZoneLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.playlist_add_outlined),
            label: const Text('Choose Card'),
          ),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            onPressed: widget.onAddTitlePressed,
            icon: const Icon(Icons.title_outlined),
            label: const Text('Header / Footer'),
          ),
          const SizedBox(height: 6),
          Text(
            'Header/Footer stays outside the grid. Normal title cards can still be added for later placement.',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if ((workspace.mergeSelectionMessage ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            workspace.mergeSelectionMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: workspace.mergeSelectionMode && !widget.canApplyMerge
                  ? null
                  : widget.onMergeCellsPressed,
              icon: Icon(
                workspace.mergeSelectionMode
                    ? Icons.check_box_outlined
                    : Icons.grid_view_outlined,
              ),
              label: Text(
                workspace.mergeSelectionMode ? 'Apply Merge' : 'Merge Cells',
              ),
            ),
            OutlinedButton.icon(
              onPressed: workspace.mergeSelectionMode
                  ? widget.onCancelMergePressed
                  : workspace.selectedMergedRegion == null
                  ? null
                  : widget.onUnmergePressed,
              icon: Icon(
                workspace.mergeSelectionMode
                    ? Icons.close_outlined
                    : Icons.call_split_outlined,
              ),
              label: Text(
                workspace.mergeSelectionMode ? 'Cancel Merge' : 'Unmerge',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: widget.onNewBlankSlide,
              icon: const Icon(Icons.add),
              label: const Text('New Blank Slide'),
            ),
            OutlinedButton.icon(
              onPressed: canPreview ? widget.onPreviewSlide : null,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview Slide'),
            ),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Slide (Coming Later)'),
            ),
          ],
        ),
      ],
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          isDense: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }
}

class _DimensionStepper extends StatelessWidget {
  const _DimensionStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            '$label:',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          onPressed: onDecrement,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Decrease $label',
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              '$value',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onIncrement,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Increase $label',
        ),
        const Spacer(),
        Text(
          '$min-$max',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 132),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
