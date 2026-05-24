import 'package:flutter/material.dart';

import 'tag_dialog_styles.dart';

class TagDialogDollarTab extends StatelessWidget {
  const TagDialogDollarTab({
    super.key,
    required this.fontScale,
  });

  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      children: [
        Text(
          'Dollar tags stay in the legacy layout for now.',
          style: TagDialogStyles.titleTextStyle(
            theme,
            fontScale,
            color: TagDialogStyles.title(theme),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This keeps the tab visible while we keep the older tag flow intact and split it back into smaller pieces step by step.',
          style: TagDialogStyles.bodyTextStyle(
            theme,
            fontScale,
            color: TagDialogStyles.body(theme),
          ),
        ),
      ],
    );
  }
}
