import 'package:flutter/material.dart';

import 'tag_detail_screen.dart';
import 'tag_dialog_styles.dart';
import 'tag_quick_apply_helper.dart';

Future<bool?> showHashTagDetailPopup(
  BuildContext context, {
  required HashTagRepository repository,
  required String tag,
  String? category,
  required double fontScale,
  Future<void> Function(int blockId)? onSelectBlockId,
  Future<void> Function(String tag)? onSelectTag,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return showDialog<bool>(
    context: navigator.context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final media = MediaQuery.of(dialogContext);
      final detailSize = TagDialogStyles.detailModalSize(media.size);
      final constrainedWidth = detailSize.width;
      final constrainedHeight = detailSize.height;

      return Dialog(
        insetPadding: TagDialogStyles.outerInset,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TagDialogStyles.borderRadius),
        ),
        clipBehavior: Clip.antiAlias,
        backgroundColor: TagDialogStyles.surface(theme),
        child: SizedBox(
          width: constrainedWidth,
          height: constrainedHeight,
          child: HashTagDetailScreen(
            repository: repository,
            tag: tag,
            category: category,
            fontScale: fontScale,
            onSelectBlockId: onSelectBlockId,
            onSelectTag: onSelectTag,
          ),
        ),
      );
    },
  );
}
