import 'package:flutter/material.dart';

class TagUnassignedCardTray extends StatelessWidget {
  const TagUnassignedCardTray({
    super.key,
    required this.availableCount,
    this.onBrowseCards,
  });

  final int availableCount;
  final VoidCallback? onBrowseCards;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCards = availableCount > 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 88 || constraints.maxWidth < 540;
            final icon = ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.32,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 14,
                    vertical: compact ? 8 : 12,
                  ),
                  child: Icon(
                    hasCards
                        ? Icons.inventory_2_outlined
                        : Icons.inbox_outlined,
                    color: theme.colorScheme.primary,
                    size: compact ? 22 : 24,
                  ),
                ),
              ),
            );

            final label = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available Cards',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: compact ? 2 : 4),
                Text(
                  hasCards
                      ? '$availableCount card${availableCount == 1 ? '' : 's'} ready to place.'
                      : 'No available cards right now.',
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                if (!compact) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Tap a cell or merged zone, then choose a card.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ],
            );

            final action = onBrowseCards == null
                ? null
                : compact
                ? IconButton.filledTonal(
                    onPressed: onBrowseCards,
                    tooltip: 'Choose Card',
                    icon: const Icon(Icons.playlist_add_outlined),
                  )
                : FilledButton.tonalIcon(
                    onPressed: onBrowseCards,
                    icon: const Icon(Icons.playlist_add_outlined),
                    label: const Text('Choose Card'),
                  );

            if (compact) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(child: label),
                  if (action != null) ...[const SizedBox(width: 12), action],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 14),
                Expanded(child: DefaultTextStyle.merge(child: label)),
                if (action != null) ...[const SizedBox(width: 14), action],
              ],
            );
          },
        ),
      ),
    );
  }
}
