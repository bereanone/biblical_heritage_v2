import 'package:flutter/material.dart';

import 'tag_presentation_prep_models.dart';

class TagPresentationSlideCard extends StatelessWidget {
  const TagPresentationSlideCard({
    super.key,
    required this.slide,
    required this.selected,
    required this.onTap,
    this.resolveItemTitle,
  });

  final TagPresentationPrepSlide slide;
  final bool selected;
  final VoidCallback onTap;
  final String Function(String itemId)? resolveItemTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = selected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
        : theme.colorScheme.surfaceContainerLowest;
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: background,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor, width: selected ? 1.5 : 0.8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      slide.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _SlideBadge(
                    label:
                        '${slide.placedCardCount} item${slide.placedCardCount == 1 ? '' : 's'}',
                  ),
                  const SizedBox(width: 6),
                  _SlideBadge(
                    label:
                        '${slide.gridLayout.rows}x${slide.gridLayout.columns}',
                  ),
                  if (slide.isBlank) ...[
                    const SizedBox(width: 6),
                    _SlideBadge(label: 'Blank'),
                  ],
                  if (slide.sourcePresentationSlideNumber != null) ...[
                    const SizedBox(width: 6),
                    _SlideBadge(
                      label: 'Source ${slide.sourcePresentationSlideNumber}',
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              if (slide.isBlank)
                Text('Blank working slide.', style: theme.textTheme.bodySmall)
              else
                Text(
                  _summaryText(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              if (selected) ...[
                const SizedBox(height: 10),
                Text(
                  'Selected slide',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _summaryText() {
    return slide.assignedItemIds
        .map((itemId) => resolveItemTitle?.call(itemId) ?? itemId)
        .take(3)
        .join(' · ');
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
