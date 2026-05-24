import 'package:flutter/material.dart';

import 'tag_dialog_styles.dart';

enum ViewerRangeAction {
  copyNoCitation,
  copyWithCitation,
  highlight,
  clearMarkup,
  addHashTag,
  addDollarTag,
  addToMemory,
  strongs,
  resetRange,
}

class ViewerRangeActionsPayload {
  const ViewerRangeActionsPayload({
    required this.label,
    required this.previewText,
    required this.startLabel,
    required this.endLabel,
  });

  final String label;
  final String previewText;
  final String startLabel;
  final String endLabel;
}

Future<ViewerRangeAction?> showViewerRangeActionsSheet(
  BuildContext context, {
  required ViewerRangeActionsPayload payload,
  required double fontScale,
  bool enableStrongs = false,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<ViewerRangeAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final colorScheme = theme.colorScheme;
      final mediaQuery = MediaQuery.of(sheetContext);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Material(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: mediaQuery.size.height * 0.82,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                children: [
                  Text(
                    'Range Actions',
                    style: TagDialogStyles.titleTextStyle(
                      theme,
                      fontScale,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    payload.label,
                    style: TagDialogStyles.bodyTextStyle(
                      theme,
                      fontScale,
                      color: TagDialogStyles.mutedBody(theme),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          payload.previewText,
                          style: TagDialogStyles.bodyTextStyle(
                            theme,
                            fontScale,
                            color: TagDialogStyles.title(theme),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          payload.label,
                          style: TagDialogStyles.bodyTextStyle(
                            theme,
                            fontScale,
                            color: TagDialogStyles.mutedBody(theme),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ActionButton(
                        icon: Icons.copy_outlined,
                        label: 'Copy No Citation',
                        fontScale: fontScale,
                        onTap: () => Navigator.of(sheetContext).pop(
                          ViewerRangeAction.copyNoCitation,
                        ),
                      ),
                      _ActionButton(
                        icon: Icons.assignment_outlined,
                        label: 'Copy With Citation',
                        fontScale: fontScale,
                        onTap: () => Navigator.of(sheetContext).pop(
                          ViewerRangeAction.copyWithCitation,
                        ),
                      ),
                      _ActionButton(
                        icon: Icons.format_paint_outlined,
                        label: 'Highlight',
                        fontScale: fontScale,
                        onTap: () => Navigator.of(sheetContext).pop(
                          ViewerRangeAction.highlight,
                        ),
                      ),
                      _ActionButton(
                        icon: Icons.layers_clear_outlined,
                        label: 'Clear Markup',
                        fontScale: fontScale,
                        onTap: () => Navigator.of(sheetContext).pop(
                          ViewerRangeAction.clearMarkup,
                        ),
                      ),
                      _ActionButton(
                        icon: Icons.tag_outlined,
                        label: 'Add # Tag',
                        fontScale: fontScale,
                        onTap: () => Navigator.of(sheetContext).pop(
                          ViewerRangeAction.addHashTag,
                        ),
                      ),
                      _ActionButton(
                        icon: Icons.attach_money_outlined,
                        label: 'Choose # Tag',
                        fontScale: fontScale,
                        onTap: () => Navigator.of(sheetContext).pop(
                          ViewerRangeAction.addDollarTag,
                        ),
                      ),
                      _ActionButton(
                        icon: Icons.menu_book_outlined,
                        label: 'Add to Memory',
                        fontScale: fontScale,
                        onTap: () => Navigator.of(sheetContext).pop(
                          ViewerRangeAction.addToMemory,
                        ),
                      ),
                      _ActionButton(
                        icon: Icons.translate_outlined,
                        label: "Strong's",
                        fontScale: fontScale,
                        enabled: enableStrongs,
                        onTap: enableStrongs
                            ? () => Navigator.of(sheetContext).pop(
                                  ViewerRangeAction.strongs,
                                )
                            : null,
                      ),
                      _ActionButton(
                        icon: Icons.close_rounded,
                        label: 'Reset Range',
                        fontScale: fontScale,
                        onTap: () => Navigator.of(sheetContext).pop(
                          ViewerRangeAction.resetRange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.fontScale,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final double fontScale;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: TagDialogStyles.buttonTextStyle(
          theme,
          fontScale,
          color: enabled
              ? colorScheme.primary
              : TagDialogStyles.disabledBody(theme),
          fontWeight: FontWeight.w700,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: enabled
            ? colorScheme.primary
            : TagDialogStyles.disabledBody(theme),
        side: BorderSide(
          color: enabled
              ? colorScheme.outline.withValues(alpha: 0.45)
              : colorScheme.outline.withValues(alpha: 0.20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
