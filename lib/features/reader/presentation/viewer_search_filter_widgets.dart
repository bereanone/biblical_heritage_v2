import 'package:flutter/material.dart';

import '../data/highlight_groups_repository.dart';
import 'viewer_book_group_colors.dart';
import 'viewer_book_label.dart';
import 'viewer_search_options.dart';

class ViewerSearchSectionFilterField extends StatelessWidget {
  const ViewerSearchSectionFilterField({
    super.key,
    required this.selectedSection,
    required this.sectionOptions,
    required this.sectionColor,
    required this.compact,
    required this.onChanged,
  });

  final String selectedSection;
  final List<ViewerSearchSectionOption> sectionOptions;
  final Color? Function(ViewerSearchSectionOption) sectionColor;
  final bool compact;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = sectionOptions.firstWhere(
      (option) => option.value == selectedSection,
      orElse: () => sectionOptions.first,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final selection = await showDialog<String>(
          context: context,
          builder: (context) => ViewerSearchSectionFilterDialog(
            selectedSection: selectedSection,
            sectionOptions: sectionOptions,
            sectionColor: sectionColor,
          ),
        );
        if (selection != null) {
          onChanged(selection);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Section Filter',
          border: const OutlineInputBorder(),
          isDense: compact,
          contentPadding: compact
              ? const EdgeInsets.fromLTRB(10, 10, 8, 8)
              : const EdgeInsets.fromLTRB(12, 12, 10, 10),
        ),
        child: Row(
          children: [
            Expanded(
              child: ViewerSearchChipLabel(
                label: selected.label,
                color: sectionColor(selected),
                indentLevel: selected.indentLevel,
                selected: true,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class ViewerSearchBookFilterField extends StatelessWidget {
  const ViewerSearchBookFilterField({
    super.key,
    required this.selectedBookLabel,
    required this.selectedBookNumber,
    required this.bookOptions,
    required this.compact,
    required this.onChanged,
  });

  final String selectedBookLabel;
  final int? selectedBookNumber;
  final List<ViewerSearchBookOption> bookOptions;
  final bool compact;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = selectedBookNumber == null
        ? theme.colorScheme.surfaceContainerHighest
        : viewerBookGroupColor(selectedBookNumber!);

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final selection = await showDialog<ViewerSearchBookFilterResult>(
          context: context,
          builder: (context) => ViewerSearchBookFilterDialog(
            selectedBookNumber: selectedBookNumber,
            bookOptions: bookOptions,
          ),
        );
        if (selection != null) {
          onChanged(selection.bookNumber);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Book Filter',
          border: const OutlineInputBorder(),
          isDense: compact,
          contentPadding: compact
              ? const EdgeInsets.fromLTRB(10, 10, 8, 8)
              : const EdgeInsets.fromLTRB(12, 12, 10, 10),
        ),
        child: Row(
          children: [
            Expanded(
              child: ViewerSearchChipLabel(
                label: selectedBookLabel,
                color: selectedColor,
                indentLevel: 0,
                selected: true,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class ViewerSearchHighlightFilterField extends StatelessWidget {
  const ViewerSearchHighlightFilterField({
    super.key,
    required this.selectedGroup,
    required this.groups,
    required this.compact,
    required this.onChanged,
  });

  final HighlightGroupRecord? selectedGroup;
  final List<HighlightGroupRecord> groups;
  final bool compact;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: groups.isEmpty
          ? null
          : () async {
              final selection = await showDialog<int>(
                context: context,
                builder: (context) => _ViewerSearchHighlightFilterDialog(
                  selectedGroupId: selectedGroup?.id,
                  groups: groups,
                ),
              );
              if (selection != null) {
                onChanged(selection);
              }
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Highlight Color',
          border: const OutlineInputBorder(),
          isDense: compact,
          contentPadding: compact
              ? const EdgeInsets.fromLTRB(10, 10, 8, 8)
              : const EdgeInsets.fromLTRB(12, 12, 10, 10),
        ),
        child: Row(
          children: [
            Expanded(
              child: selectedGroup == null
                  ? Text(
                      groups.isEmpty ? 'No highlight groups' : 'Choose color',
                      style: theme.textTheme.bodyMedium,
                    )
                  : Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: selectedGroup!.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            selectedGroup!.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class ViewerSearchSectionFilterDialog extends StatelessWidget {
  const ViewerSearchSectionFilterDialog({
    super.key,
    required this.selectedSection,
    required this.sectionOptions,
    required this.sectionColor,
  });

  final String selectedSection;
  final List<ViewerSearchSectionOption> sectionOptions;
  final Color? Function(ViewerSearchSectionOption) sectionColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Section Filter',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap any section below.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sectionOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final option = sectionOptions[index];
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: ViewerSearchChipLabel(
                        label: option.label,
                        color: sectionColor(option),
                        indentLevel: option.indentLevel,
                        selected: option.value == selectedSection,
                        onTap: () => Navigator.of(context).pop(option.value),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ViewerSearchBookFilterDialog extends StatelessWidget {
  const ViewerSearchBookFilterDialog({
    super.key,
    required this.selectedBookNumber,
    required this.bookOptions,
  });

  final int? selectedBookNumber;
  final List<ViewerSearchBookOption> bookOptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Book Filter',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap a book to narrow the results.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: bookOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final option = bookOptions[index];
                    final color = option.bookNumber == null
                        ? theme.colorScheme.surfaceContainerHighest
                        : viewerBookGroupColor(option.bookNumber!);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: ViewerSearchChipLabel(
                        label: option.label,
                        color: color,
                        indentLevel: 0,
                        selected: option.bookNumber == selectedBookNumber,
                        onTap: () => Navigator.of(context).pop(
                          ViewerSearchBookFilterResult(option.bookNumber),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewerSearchHighlightFilterDialog extends StatelessWidget {
  const _ViewerSearchHighlightFilterDialog({
    required this.selectedGroupId,
    required this.groups,
  });

  final int? selectedGroupId;
  final List<HighlightGroupRecord> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Highlight Color',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap a color group to look up its verses.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    final selected = group.id == selectedGroupId;
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      tileColor: selected
                          ? theme.colorScheme.surfaceContainerHigh
                          : null,
                      leading: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: group.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(group.name),
                      trailing: selected
                          ? Icon(
                              Icons.check,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(group.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ViewerSearchChipLabel extends StatelessWidget {
  const ViewerSearchChipLabel({
    super.key,
    required this.label,
    required this.color,
    required this.indentLevel,
    required this.selected,
    this.onTap,
  });

  final String label;
  final Color? color;
  final int indentLevel;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = color ?? theme.colorScheme.surfaceContainerHighest;
    final chipColor = indentLevel == 0
        ? viewerGroupTone(context, baseColor, fill: true)
        : viewerGroupTone(context, baseColor, fill: false);

    return Padding(
      padding: EdgeInsets.only(left: indentLevel == 0 ? 0 : 18),
      child: ViewerBookLabel(
        label: label,
        color: chipColor,
        selected: selected,
        onTap: onTap ?? () {},
      ),
    );
  }
}

class ViewerSearchActionChip extends StatelessWidget {
  const ViewerSearchActionChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
          color: theme.colorScheme.surfaceContainerLowest,
        ),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
