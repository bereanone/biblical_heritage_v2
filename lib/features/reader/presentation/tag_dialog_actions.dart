import 'package:flutter/material.dart';

import 'tag_dialog_styles.dart';

class TagDialogActions extends StatelessWidget {
  const TagDialogActions({
    super.key,
    required this.selectionLabel,
    required this.currentTag,
    required this.defaultTag,
    required this.categoryController,
    required this.tagController,
    required this.working,
    required this.rapidTagSessionActive,
    required this.rapidTagSessionRemaining,
    required this.onUseDefault,
    required this.onSaveDefault,
    required this.onApplySelection,
    required this.onShowInstructions,
    required this.onRenameCurrentTag,
    required this.onTagSubmitted,
    required this.onStartRapidTagSession,
    required this.onEndRapidTagSession,
  });

  final String selectionLabel;
  final String currentTag;
  final String? defaultTag;
  final TextEditingController categoryController;
  final TextEditingController tagController;
  final bool working;
  final bool rapidTagSessionActive;
  final int? rapidTagSessionRemaining;
  final VoidCallback? onUseDefault;
  final VoidCallback onSaveDefault;
  final VoidCallback onApplySelection;
  final VoidCallback onShowInstructions;
  final VoidCallback onRenameCurrentTag;
  final VoidCallback onTagSubmitted;
  final ValueChanged<int?> onStartRapidTagSession;
  final VoidCallback onEndRapidTagSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = TagDialogStyles.accent(theme);
    final accentText = theme.brightness == Brightness.dark
        ? theme.colorScheme.onPrimary
        : Colors.white;
    final rapidSummary = rapidTagSessionActive
        ? rapidTagSessionRemaining == null
              ? 'Active: unlimited tags'
              : 'Active: ${rapidTagSessionRemaining!} tag${rapidTagSessionRemaining == 1 ? '' : 's'} left'
        : 'Off';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                selectionLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: TagDialogStyles.title(theme),
                ),
              ),
            ),
            const SizedBox(width: 10),
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
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onUseDefault,
              style: OutlinedButton.styleFrom(
                foregroundColor: TagDialogStyles.accent(theme),
                side: BorderSide(color: TagDialogStyles.outlineColor(theme)),
                backgroundColor: TagDialogStyles.surface(theme),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: TagDialogStyles.fittedButtonLabel('Use'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onSaveDefault,
              style: OutlinedButton.styleFrom(
                foregroundColor: TagDialogStyles.accent(theme),
                side: BorderSide(color: TagDialogStyles.outlineColor(theme)),
                backgroundColor: TagDialogStyles.surface(theme),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: TagDialogStyles.fittedButtonLabel('Save'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Card(
          color: TagDialogStyles.surfaceHigh(theme),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Rapid Tag Session',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: TagDialogStyles.title(theme),
                        ),
                      ),
                    ),
                    Text(
                      rapidSummary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: TagDialogStyles.body(theme),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Turn this on to tag multiple verses without extra prompts. '
                  'Use End Session to stop rapid tagging.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: TagDialogStyles.body(theme),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: working
                          ? null
                          : () => onStartRapidTagSession(5),
                      child: const Text('5 tags'),
                    ),
                    FilledButton.tonal(
                      onPressed: working
                          ? null
                          : () => onStartRapidTagSession(10),
                      child: const Text('10 tags'),
                    ),
                    FilledButton.tonal(
                      onPressed: working
                          ? null
                          : () => onStartRapidTagSession(null),
                      child: const Text('Unlimited'),
                    ),
                    OutlinedButton(
                      onPressed: rapidTagSessionActive
                          ? onEndRapidTagSession
                          : null,
                      child: const Text('End rapid tag session'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 460;
            final tagField = TextField(
              controller: tagController,
              style: theme.textTheme.titleLarge?.copyWith(
                color: TagDialogStyles.title(theme),
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                labelText: '# tag',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: TagDialogStyles.surface(theme),
              ),
              onSubmitted: (_) => onTagSubmitted(),
            );
            final tagButton = SizedBox(
              width: isNarrow ? 92 : 112,
              height: isNarrow ? 60 : 62,
              child: FilledButton(
                onPressed: working ? null : onApplySelection,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: accentText,
                  textStyle: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: TagDialogStyles.fittedButtonLabel(
                  'Tag\nVerse',
                  maxLines: 2,
                ),
              ),
            );
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tagField,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: tagButton),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tagField),
                const SizedBox(width: 8),
                tagButton,
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        TextField(
          controller: categoryController,
          decoration: InputDecoration(
            labelText: 'Category',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: TagDialogStyles.surfaceHigh(theme),
          ),
          style: theme.textTheme.titleMedium?.copyWith(
            color: TagDialogStyles.title(theme),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: onShowInstructions,
              icon: const Icon(Icons.help_outline, size: 18),
              label: TagDialogStyles.fittedButtonLabel('Instructions'),
              style: OutlinedButton.styleFrom(
                foregroundColor: TagDialogStyles.accent(theme),
                side: BorderSide(color: TagDialogStyles.outlineColor(theme)),
                backgroundColor: TagDialogStyles.surface(theme),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onRenameCurrentTag,
              icon: const Icon(Icons.drive_file_rename_outline, size: 18),
              label: TagDialogStyles.fittedButtonLabel('Rename current tag'),
              style: OutlinedButton.styleFrom(
                foregroundColor: TagDialogStyles.accent(theme),
                side: BorderSide(color: TagDialogStyles.outlineColor(theme)),
                backgroundColor: TagDialogStyles.surface(theme),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
