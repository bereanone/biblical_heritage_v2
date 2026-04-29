import 'package:flutter/material.dart';

class TagDialogDollarTab extends StatelessWidget {
  const TagDialogDollarTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      children: [
        Text(
          'Dollar tags stay in the legacy layout for now.',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This keeps the tab visible while we keep the older tag flow intact and split it back into smaller pieces step by step.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}
