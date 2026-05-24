part of 'library_book_reader_screen.dart';

enum LibrarySelectionRangeAction {
  copyNoCitation,
  copyWithCitation,
  copyWithMarkup,
  copyWithMarkupAndCitation,
  highlight,
  addHashTag,
  clearMarkup,
  resetRange,
}

class LibrarySelectionRangeActionsPayload {
  const LibrarySelectionRangeActionsPayload({
    required this.referenceLabel,
    required this.previewText,
    required this.enableClearMarkup,
  });

  final String referenceLabel;
  final String previewText;
  final bool enableClearMarkup;
}

Future<LibrarySelectionRangeAction?> showLibrarySelectionRangeActionsSheet(
  BuildContext context, {
  required LibrarySelectionRangeActionsPayload payload,
  required double fontScale,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<LibrarySelectionRangeAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final colorScheme = theme.colorScheme;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Material(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        payload.referenceLabel,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          payload.previewText,
                          style: TagDialogStyles.bodyTextStyle(
                            theme,
                            fontScale,
                            color: TagDialogStyles.title(theme),
                            fontWeight: FontWeight.w500,
                            height: 1.22,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _SelectionActionButton(
                            icon: Icons.copy_outlined,
                            label: 'Copy No Citation',
                            fontScale: fontScale,
                            onTap: () => Navigator.of(
                              sheetContext,
                            ).pop(LibrarySelectionRangeAction.copyNoCitation),
                          ),
                          _SelectionActionButton(
                            icon: Icons.assignment_outlined,
                            label: 'Copy With Citation',
                            fontScale: fontScale,
                            onTap: () => Navigator.of(
                              sheetContext,
                            ).pop(LibrarySelectionRangeAction.copyWithCitation),
                          ),
                          _SelectionActionButton(
                            icon: Icons.copy_all_outlined,
                            label: 'Copy With Markup',
                            fontScale: fontScale,
                            onTap: () => Navigator.of(
                              sheetContext,
                            ).pop(LibrarySelectionRangeAction.copyWithMarkup),
                          ),
                          _SelectionActionButton(
                            icon: Icons.copy_all_outlined,
                            label: 'Copy Markup + Citation',
                            fontScale: fontScale,
                            onTap: () => Navigator.of(sheetContext).pop(
                              LibrarySelectionRangeAction
                                  .copyWithMarkupAndCitation,
                            ),
                          ),
                          _SelectionActionButton(
                            icon: Icons.format_paint_outlined,
                            label: 'Highlight',
                            fontScale: fontScale,
                            onTap: () => Navigator.of(
                              sheetContext,
                            ).pop(LibrarySelectionRangeAction.highlight),
                          ),
                          _SelectionActionButton(
                            icon: Icons.layers_clear_outlined,
                            label: 'Clear Markup',
                            fontScale: fontScale,
                            enabled: payload.enableClearMarkup,
                            onTap: () => Navigator.of(
                              sheetContext,
                            ).pop(LibrarySelectionRangeAction.clearMarkup),
                          ),
                          _SelectionActionButton(
                            icon: Icons.tag_outlined,
                            label: 'Add # Tag',
                            fontScale: fontScale,
                            onTap: () => Navigator.of(
                              sheetContext,
                            ).pop(LibrarySelectionRangeAction.addHashTag),
                          ),
                          _SelectionActionButton(
                            icon: Icons.menu_book_outlined,
                            label: 'Add to Memory',
                            fontScale: fontScale,
                            enabled: false,
                          ),
                          _SelectionActionButton(
                            icon: Icons.translate_outlined,
                            label: "Strong's",
                            fontScale: fontScale,
                            enabled: false,
                          ),
                          _SelectionActionButton(
                            icon: Icons.close_rounded,
                            label: 'Reset Range',
                            fontScale: fontScale,
                            onTap: () => Navigator.of(
                              sheetContext,
                            ).pop(LibrarySelectionRangeAction.resetRange),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SelectionActionButton extends StatelessWidget {
  const _SelectionActionButton({
    required this.icon,
    required this.label,
    required this.fontScale,
    this.onTap,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
