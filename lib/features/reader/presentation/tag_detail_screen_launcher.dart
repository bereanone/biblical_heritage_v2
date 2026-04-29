import 'package:flutter/material.dart';

import 'tag_detail_screen.dart';
import 'tag_dialog_styles.dart';
import 'tag_quick_apply_helper.dart';

Future<bool?> showHashTagDetailPopup(
  BuildContext context, {
  required HashTagRepository repository,
  required String tag,
  Future<void> Function(int blockId)? onSelectBlockId,
  Future<void> Function(String tag)? onSelectTag,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close tag details',
    barrierColor: Colors.black.withValues(alpha: 0.36),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final theme = Theme.of(dialogContext);
      return SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 560),
            child: Dialog(
              insetPadding: TagDialogStyles.outerInset,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  TagDialogStyles.borderRadius,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              backgroundColor: TagDialogStyles.surface(theme),
              child: HashTagDetailScreen(
                repository: repository,
                tag: tag,
                onSelectBlockId: onSelectBlockId,
                onSelectTag: onSelectTag,
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(fade),
          child: child,
        ),
      );
    },
  );
}
