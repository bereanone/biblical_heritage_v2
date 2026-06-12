import 'package:flutter/material.dart';

import 'tag_presentation_prep_models.dart';
import 'tag_presentation_prep_state.dart';
import 'presentation_ui_helpers.dart';

class TagSlideNavigatorPanel extends StatefulWidget {
  const TagSlideNavigatorPanel({
    super.key,
    required this.workspace,
    required this.fontScale,
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
    required this.onSavePresentation,
    required this.onSavedPresentations,
  });

  final TagPresentationPrepWorkspace workspace;
  final double fontScale;
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
  final VoidCallback onSavePresentation;
  final VoidCallback onSavedPresentations;

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
    final headerStyle = presentationTextStyle(
      context,
      theme.textTheme.titleMedium,
      widget.fontScale,
      fontWeight: FontWeight.w700,
      minFontSize: 17,
      maxFontSize: 26,
    );
    final headerRow = Row(
      children: [
        Expanded(
          child: Text(
            'Slide Controls',
            style: headerStyle,
          ),
        ),
        _SlideBadge(label: selectedSlideLabel, fontScale: widget.fontScale),
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
    final buttonTextStyle = presentationTextStyle(
      context,
      theme.textTheme.labelLarge,
      widget.fontScale,
      fontWeight: FontWeight.w700,
      minFontSize: 14.5,
      maxFontSize: 18.5,
    );
    final dropdownItemStyle = presentationTextStyle(
      context,
      theme.textTheme.bodyMedium,
      widget.fontScale,
      minFontSize: 14,
      maxFontSize: 18,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Choose a slide, adjust the grid, open a blank slide, or preview the active canvas.',
          style: presentationTextStyle(
            context,
            theme.textTheme.bodyMedium,
            widget.fontScale,
            minFontSize: 14,
            maxFontSize: 18,
          ),
        ),
        const SizedBox(height: 12),
        _DropdownRow<TagPresentationAspectRatioPreset>(
          label: 'Display target',
          fontScale: widget.fontScale,
          value: aspectRatio.preset,
          items: [
            DropdownMenuItem(
              value: TagPresentationAspectRatioPreset.sixteenByNine,
              child: Text('16:9 Widescreen', style: dropdownItemStyle),
            ),
            DropdownMenuItem(
              value: TagPresentationAspectRatioPreset.fourByThree,
              child: Text('4:3 Projector', style: dropdownItemStyle),
            ),
            DropdownMenuItem(
              value: TagPresentationAspectRatioPreset.sixteenByTen,
              child: Text('16:10', style: dropdownItemStyle),
            ),
            DropdownMenuItem(
              value: TagPresentationAspectRatioPreset.nineBySixteen,
              child: Text('9:16 Phone Portrait', style: dropdownItemStyle),
            ),
            DropdownMenuItem(
              value: TagPresentationAspectRatioPreset.custom,
              child: Text('Custom', style: dropdownItemStyle),
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
                style: presentationTextStyle(
                  context,
                  theme.textTheme.labelLarge,
                  widget.fontScale,
                  minFontSize: 13.5,
                  maxFontSize: 17.5,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _DimensionStepper(
          label: 'Rows',
          fontScale: widget.fontScale,
          value: rows,
          min: 1,
          max: 4,
          onDecrement: rows > 1 ? () => widget.onRowsChanged(rows - 1) : null,
          onIncrement: rows < 4 ? () => widget.onRowsChanged(rows + 1) : null,
        ),
        const SizedBox(height: 8),
        _DimensionStepper(
          label: 'Columns',
          fontScale: widget.fontScale,
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
          style: presentationTextStyle(
            context,
            theme.textTheme.bodyMedium,
            widget.fontScale,
            minFontSize: 14,
            maxFontSize: 18,
          ),
        ),
        const SizedBox(height: 12),
        if (workspace.hasSelectedZone) ...[
          FilledButton.tonalIcon(
            onPressed: widget.onChooseCardPressed,
            icon: const Icon(Icons.playlist_add_outlined),
            label: const Text('Choose Card'),
            style: FilledButton.styleFrom(textStyle: buttonTextStyle),
          ),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            onPressed: widget.onAddTitlePressed,
            icon: const Icon(Icons.title_outlined),
            label: const Text('Header / Footer'),
            style: FilledButton.styleFrom(textStyle: buttonTextStyle),
          ),
          const SizedBox(height: 6),
          Text(
            workspace.selectedZoneLabel,
            style: presentationTextStyle(
              context,
              theme.textTheme.labelLarge,
              widget.fontScale,
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w600,
              minFontSize: 12.5,
              maxFontSize: 15.5,
            ),
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.playlist_add_outlined),
            label: const Text('Choose Card'),
            style: OutlinedButton.styleFrom(textStyle: buttonTextStyle),
          ),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            onPressed: widget.onAddTitlePressed,
            icon: const Icon(Icons.title_outlined),
            label: const Text('Header / Footer'),
            style: FilledButton.styleFrom(textStyle: buttonTextStyle),
          ),
          const SizedBox(height: 6),
          Text(
            'Header/Footer stays outside the grid. Normal title cards can still be added for later placement.',
            style: presentationTextStyle(
              context,
              theme.textTheme.labelLarge,
              widget.fontScale,
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w600,
              minFontSize: 12.5,
              maxFontSize: 15.5,
            ),
          ),
        ],
        if ((workspace.mergeSelectionMessage ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            workspace.mergeSelectionMessage!,
            style: presentationTextStyle(
              context,
              theme.textTheme.bodyMedium,
              widget.fontScale,
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
              minFontSize: 14,
              maxFontSize: 18,
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
              style: FilledButton.styleFrom(textStyle: buttonTextStyle),
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
              style: OutlinedButton.styleFrom(textStyle: buttonTextStyle),
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
              style: FilledButton.styleFrom(textStyle: buttonTextStyle),
            ),
            OutlinedButton.icon(
              onPressed: canPreview ? widget.onPreviewSlide : null,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview Slide'),
              style: OutlinedButton.styleFrom(textStyle: buttonTextStyle),
            ),
            OutlinedButton.icon(
              onPressed: workspace.hasSlides
                  ? widget.onSavePresentation
                  : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Presentation'),
              style: OutlinedButton.styleFrom(textStyle: buttonTextStyle),
            ),
            OutlinedButton.icon(
              onPressed: widget.onSavedPresentations,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Saved Presentations'),
              style: OutlinedButton.styleFrom(textStyle: buttonTextStyle),
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
    required this.fontScale,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final double fontScale;
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
          style: presentationTextStyle(
            context,
            theme.textTheme.labelLarge,
            fontScale,
            fontWeight: FontWeight.w700,
            minFontSize: 13.5,
            maxFontSize: 17.5,
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          style: presentationTextStyle(
            context,
            theme.textTheme.bodyMedium,
            fontScale,
            minFontSize: 14,
            maxFontSize: 18,
          ),
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
    required this.fontScale,
    required this.value,
    required this.min,
    required this.max,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String label;
  final double fontScale;
  final int value;
  final int min;
  final int max;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonExtent = presentationScaledSize(
      context,
      44,
      fontScale,
      min: 42,
      max: 52,
    );
    final iconSize = presentationScaledSize(
      context,
      22,
      fontScale,
      min: 18,
      max: 26,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        final labelStyle = presentationTextStyle(
          context,
          theme.textTheme.labelLarge,
          fontScale,
          fontWeight: FontWeight.w700,
          minFontSize: 13.5,
          maxFontSize: 17.5,
        );
        final valueStyle = presentationTextStyle(
          context,
          theme.textTheme.labelLarge,
          fontScale,
          fontWeight: FontWeight.w700,
          minFontSize: 13.5,
          maxFontSize: 17.5,
        );
        final rangeStyle = presentationTextStyle(
          context,
          theme.textTheme.labelLarge ?? theme.textTheme.labelSmall,
          fontScale,
          color: theme.colorScheme.outline,
          minFontSize: 12.5,
          maxFontSize: 15.5,
        );

        if (isNarrow) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('$label:', style: labelStyle),
              IconButton(
                onPressed: onDecrement,
                constraints: BoxConstraints.tightFor(
                  width: buttonExtent,
                  height: buttonExtent,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.remove_circle_outline, size: iconSize),
                tooltip: 'Decrease $label',
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('$value', style: valueStyle),
                ),
              ),
              IconButton(
                onPressed: onIncrement,
                constraints: BoxConstraints.tightFor(
                  width: buttonExtent,
                  height: buttonExtent,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.add_circle_outline, size: iconSize),
                tooltip: 'Increase $label',
              ),
              Text('$min-$max', style: rangeStyle),
            ],
          );
        }

        return Row(
          children: [
            SizedBox(width: 90, child: Text('$label:', style: labelStyle)),
            IconButton(
              onPressed: onDecrement,
              constraints: BoxConstraints.tightFor(
                width: buttonExtent,
                height: buttonExtent,
              ),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.remove_circle_outline, size: iconSize),
              tooltip: 'Decrease $label',
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text('$value', style: valueStyle),
              ),
            ),
            IconButton(
              onPressed: onIncrement,
              constraints: BoxConstraints.tightFor(
                width: buttonExtent,
                height: buttonExtent,
              ),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.add_circle_outline, size: iconSize),
              tooltip: 'Increase $label',
            ),
            const Spacer(),
            Text('$min-$max', style: rangeStyle),
          ],
        );
      },
    );
  }
}

class _SlideBadge extends StatelessWidget {
  const _SlideBadge({required this.label, required this.fontScale});

  final String label;
  final double fontScale;

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
            style: presentationTextStyle(
              context,
              Theme.of(context).textTheme.labelLarge,
              fontScale,
              fontWeight: FontWeight.w700,
              minFontSize: 12.5,
              maxFontSize: 15.5,
            ),
          ),
        ),
      ),
    );
  }
}
