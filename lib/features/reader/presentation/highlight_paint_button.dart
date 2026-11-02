import 'package:flutter/material.dart';

/// The same paintbrush identifies the action in the reader and color setup.
class HighlightPaintButton extends StatelessWidget {
  const HighlightPaintButton({
    super.key,
    required this.onPressed,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!compact) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.brush_outlined),
        label: const Text('Apply Highlight'),
      );
    }
    return Tooltip(
      message: onPressed == null
          ? 'Select text first, then use the paintbrush to apply highlighting'
          : 'Paint: apply highlighting to selected text',
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 44),
          maximumSize: const Size(48, 44),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.brush_outlined, size: 21),
              Text(
                'Paint',
                style: TextStyle(fontSize: 10, height: 1),
                textScaler: TextScaler.noScaling,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
