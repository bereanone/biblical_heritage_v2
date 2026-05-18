import 'package:flutter/material.dart';

enum ReaderSearchMode { bible, elibrary }

Future<ReaderSearchMode?> showReaderSearchModePicker(BuildContext context) {
  return showDialog<ReaderSearchMode>(
    context: context,
    builder: (context) => const _ReaderSearchModePickerDialog(),
  );
}

class _ReaderSearchModePickerDialog extends StatelessWidget {
  const _ReaderSearchModePickerDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Search'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose whether to search the Bible or the eLibrary.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<ReaderSearchMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment<ReaderSearchMode>(
                value: ReaderSearchMode.bible,
                icon: Icon(Icons.menu_book_outlined, size: 18),
                label: Text('Bible'),
              ),
              ButtonSegment<ReaderSearchMode>(
                value: ReaderSearchMode.elibrary,
                icon: Icon(Icons.library_books_outlined, size: 18),
                label: Text('eLibrary'),
              ),
            ],
            selected: const {ReaderSearchMode.bible},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) return;
              Navigator.of(context).pop(selection.first);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
