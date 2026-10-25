import 'package:flutter/material.dart';

const readerSelectionHelp =
    'Press and hold a word to select it. Drag either end handle to expand or '
    'shrink the selection, including down to one word. You can release a handle '
    'and drag it again without opening a menu.\n\n'
    'Tap or click inside the selected text to open Range Actions. Tap or click '
    'outside the selected text and its handles to deselect it.\n\n'
    'Use the paintbrush to apply the current highlight style. Tap the Highlight '
    'color preview to open Color Setup. Highlight also remains available in '
    'Range Actions. Clear Markup removes the markup and clears the selection.';

Future<void> showReaderSelectionHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Selection and highlighting'),
    content: const SingleChildScrollView(child: Text(readerSelectionHelp)),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  ),
);
