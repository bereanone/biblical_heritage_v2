import 'package:flutter/material.dart';

import 'tag_dialog_styles.dart';

class TagDialogHeader extends StatelessWidget {
  const TagDialogHeader({
    super.key,
    required this.title,
    required this.fontScale,
    required this.onClose,
    required this.onShowInstructions,
    required this.onFindText,
    required this.onImportClipboard,
    required this.onRenameCurrentTag,
    required this.onViewTrash,
    this.defaultTag,
    this.onUseDefault,
    this.onSaveDefault,
    this.legacyStyle = false,
  });

  final String title;
  final double fontScale;
  final VoidCallback onClose;
  final VoidCallback onShowInstructions;
  final VoidCallback onFindText;
  final VoidCallback onImportClipboard;
  final VoidCallback onRenameCurrentTag;
  final VoidCallback onViewTrash;
  final String? defaultTag;
  final VoidCallback? onUseDefault;
  final VoidCallback? onSaveDefault;
  final bool legacyStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = TagDialogStyles.headerDecoration(theme);

    return Container(
      decoration: decoration,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TagDialogStyles.titleTextStyle(
                    theme,
                    fontScale,
                    color: TagDialogStyles.title(theme),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close),
                color: TagDialogStyles.body(theme),
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 380;
              return Wrap(
                spacing: 10,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _TagHeaderChip(
                        icon: Icons.help_outline,
                        label: '',
                        onPressed: onShowInstructions,
                        compact: compact,
                        fontScale: fontScale,
                        showLabel: false,
                      ),
                      _TagHeaderChip(
                        icon: Icons.search,
                        label: 'Find Text',
                        onPressed: onFindText,
                        compact: compact,
                        fontScale: fontScale,
                      ),
                      _TagHeaderChip(
                        icon: Icons.restore_from_trash_outlined,
                        label: 'View Trash',
                        onPressed: onViewTrash,
                        compact: compact,
                        fontScale: fontScale,
                        tooltip: 'View global trash',
                      ),
                      OutlinedButton(
                        onPressed: onImportClipboard,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TagDialogStyles.accent(theme),
                          side: BorderSide(
                            color: TagDialogStyles.outlineColor(theme),
                          ),
                          backgroundColor: TagDialogStyles.surface(theme),
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 10 : 14,
                            vertical: compact ? 10 : 12,
                          ),
                          visualDensity: VisualDensity.compact,
                          textStyle: TagDialogStyles.buttonTextStyle(
                            theme,
                            fontScale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: compact
                            ? Icon(
                                Icons.arrow_downward_rounded,
                                size: 18,
                                color: TagDialogStyles.body(theme),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_downward_rounded, size: 18),
                                ],
                              ),
                      ),
                      OutlinedButton(
                        onPressed: onRenameCurrentTag,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TagDialogStyles.accent(theme),
                          side: BorderSide(
                            color: TagDialogStyles.outlineColor(theme),
                          ),
                          backgroundColor: TagDialogStyles.surface(theme),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                          textStyle: TagDialogStyles.buttonTextStyle(
                            theme,
                            fontScale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: TagDialogStyles.fittedButtonLabel(
                          'Rename',
                          style: TagDialogStyles.buttonTextStyle(
                            theme,
                            fontScale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (defaultTag != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Default: $defaultTag',
                            style: TagDialogStyles.bodyTextStyle(
                              theme,
                              fontScale,
                              color: TagDialogStyles.body(theme),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      OutlinedButton(
                        onPressed: onUseDefault,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TagDialogStyles.accent(theme),
                          side: BorderSide(
                            color: TagDialogStyles.outlineColor(theme),
                          ),
                          backgroundColor: TagDialogStyles.surface(theme),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                          textStyle: TagDialogStyles.buttonTextStyle(
                            theme,
                            fontScale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(
                          'Use',
                          style: TagDialogStyles.buttonTextStyle(
                            theme,
                            fontScale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: onSaveDefault,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TagDialogStyles.accent(theme),
                          side: BorderSide(
                            color: TagDialogStyles.outlineColor(theme),
                          ),
                          backgroundColor: TagDialogStyles.surface(theme),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                          textStyle: TagDialogStyles.buttonTextStyle(
                            theme,
                            fontScale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(
                          'Make Default',
                          style: TagDialogStyles.buttonTextStyle(
                            theme,
                            fontScale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TagHeaderChip extends StatelessWidget {
  const _TagHeaderChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.compact,
    required this.fontScale,
    this.tooltip,
    this.showLabel = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool compact;
  final double fontScale;
  final String? tooltip;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: TagDialogStyles.accent(theme),
        side: BorderSide(color: TagDialogStyles.outlineColor(theme)),
        backgroundColor: TagDialogStyles.surface(theme),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 16,
          vertical: compact ? 10 : 14,
        ),
        minimumSize: Size(compact ? 38 : 0, 38),
        textStyle: TagDialogStyles.buttonTextStyle(
          theme,
          fontScale,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: compact
          ? Icon(icon, size: 18)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                if (showLabel) ...[
                  const SizedBox(width: 6),
                  TagDialogStyles.fittedButtonLabel(
                    label,
                    style: TagDialogStyles.buttonTextStyle(
                      theme,
                      fontScale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
    );
    final message = tooltip?.trim() ?? '';
    if (message.isEmpty) return button;
    return Tooltip(message: message, child: button);
  }
}
