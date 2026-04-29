import 'package:flutter/material.dart';

import 'tag_dialog_styles.dart';

class TagDialogHeader extends StatelessWidget {
  const TagDialogHeader({
    super.key,
    required this.title,
    required this.onClose,
    required this.onShowInstructions,
    required this.onFindText,
    required this.onImportClipboard,
    required this.onRenameCurrentTag,
    this.defaultTag,
    this.onUseDefault,
    this.onSaveDefault,
    this.legacyStyle = false,
  });

  final String title;
  final VoidCallback onClose;
  final VoidCallback onShowInstructions;
  final VoidCallback onFindText;
  final VoidCallback onImportClipboard;
  final VoidCallback onRenameCurrentTag;
  final String? defaultTag;
  final VoidCallback? onUseDefault;
  final VoidCallback? onSaveDefault;
  final bool legacyStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = legacyStyle
        ? const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF0DCCB), Color(0xFFF6EEE3), Color(0xFFF8F1E8)],
            ),
            border: Border(
              bottom: BorderSide(color: Color(0xFFCFA36C), width: 0.6),
            ),
          )
        : theme.brightness == Brightness.dark
        ? BoxDecoration(
            color: TagDialogStyles.surfaceHigh(theme),
            border: Border(
              bottom: BorderSide(
                color: TagDialogStyles.outlineColor(theme),
                width: 0.6,
              ),
            ),
          )
        : BoxDecoration(
            color: TagDialogStyles.surfaceHigh(theme),
            border: const Border(
              bottom: BorderSide(color: TagDialogStyles.outline, width: 0.6),
            ),
          );

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
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: legacyStyle ? 24 : 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    color: legacyStyle
                        ? const Color(0xFF4A2B12)
                        : TagDialogStyles.title(theme),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close),
                color: legacyStyle
                    ? const Color(0xFF7B4A1D)
                    : TagDialogStyles.body(theme),
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
                        showLabel: false,
                      ),
                      _TagHeaderChip(
                        icon: Icons.search,
                        label: 'Find',
                        onPressed: onFindText,
                        compact: compact,
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
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: compact
                            ? const Icon(Icons.arrow_downward_rounded, size: 18)
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
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: TagDialogStyles.fittedButtonLabel('Rename'),
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
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: TagDialogStyles.body(theme),
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
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: TagDialogStyles.fittedButtonLabel('Use'),
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
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: TagDialogStyles.fittedButtonLabel('Make Default'),
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
    this.showLabel = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool compact;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
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
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      child: compact
          ? Icon(icon, size: 18)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                if (showLabel) ...[
                  const SizedBox(width: 6),
                  TagDialogStyles.fittedButtonLabel(label),
                ],
              ],
            ),
    );
  }
}
