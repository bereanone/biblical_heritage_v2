import 'package:flutter/material.dart';

/// Keep every action visible without reducing the reader's chosen text size.
class TagEntryActions extends StatelessWidget {
  const TagEntryActions({
    super.key,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onTrash,
    this.onTrashLongPress,
    required this.foregroundColor,
  });

  final VoidCallback onEdit;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onTrash;
  final VoidCallback? onTrashLongPress;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A rotated phone remains compact; tablets also need enough room in
        // the current pane before showing the wider controls.
        final tabletSized = MediaQuery.sizeOf(context).shortestSide >= 600;
        final wide = tabletSized && constraints.maxWidth >= 480;
        final compactStyle = TextButton.styleFrom(
          foregroundColor: foregroundColor,
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontSize: 14),
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 8, vertical: 8),
        );
        Widget move(String direction, VoidCallback? onPressed) => Tooltip(
          message: 'Move $direction',
          child: wide
              ? TextButton.icon(
                  onPressed: onPressed,
                  style: compactStyle,
                  icon: Icon(
                    direction == 'up'
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 22,
                  ),
                  label: Text('Move $direction'),
                )
              : TextButton(
                  onPressed: onPressed,
                  style: compactStyle.copyWith(
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        direction == 'up'
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 18,
                      ),
                      Text('Move\n$direction', textAlign: TextAlign.center),
                    ],
                  ),
                ),
        );

        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: wide ? 8 : 0,
            runSpacing: 4,
            children: [
              Tooltip(
                message: 'Edit item',
                child: TextButton.icon(
                  onPressed: onEdit,
                  style: compactStyle,
                  icon: const Icon(Icons.edit_outlined, size: 22),
                  label: const Text('Edit'),
                ),
              ),
              move('up', onMoveUp),
              move('down', onMoveDown),
              GestureDetector(
                onLongPress: onTrashLongPress,
                child: Tooltip(
                  message: 'Move to Trash',
                  child: TextButton.icon(
                    onPressed: onTrash,
                    style: compactStyle.copyWith(
                      foregroundColor: WidgetStatePropertyAll(
                        Theme.of(context).colorScheme.error,
                      ),
                    ),
                    icon: const Icon(Icons.delete, size: 22),
                    label: const Text('Trash'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
