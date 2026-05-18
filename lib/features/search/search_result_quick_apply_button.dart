import 'package:flutter/material.dart';

import '../reader/presentation/tag_dialog_styles.dart';

class SearchResultQuickApplyButton extends StatelessWidget {
  const SearchResultQuickApplyButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Add to #tag',
  });

  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 52,
        height: 32,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(38, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            foregroundColor: TagDialogStyles.accent(theme),
            side: BorderSide(color: TagDialogStyles.outlineColor(theme)),
            backgroundColor: TagDialogStyles.surface(theme),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
          child: const Text('Add', style: TextStyle(height: 1)),
        ),
      ),
    );
  }
}
