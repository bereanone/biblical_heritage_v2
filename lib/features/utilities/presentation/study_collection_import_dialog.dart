import 'package:flutter/material.dart';

import '../data/pioneer_study_collection_service.dart';

Future<Set<String>?> showStudyCollectionImportDialog(
  BuildContext context,
  StudyCollectionInventory inventory,
) {
  final selectable = inventory.books
      .where(
        (book) =>
            book.status == StudyCollectionBookStatus.newBook ||
            book.status == StudyCollectionBookStatus.update,
      )
      .toList();
  final selected = selectable.map((book) => book.workId).toSet();
  var query = '';
  return showDialog<Set<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final visible = selectable
            .where(
              (book) =>
                  '${book.title} ${book.author}'.toLowerCase().contains(query),
            )
            .toList();
        int count(StudyCollectionBookStatus status) =>
            inventory.books.where((book) => book.status == status).length;
        return AlertDialog(
          title: const Text('Check for New Books'),
          content: SizedBox(
            width: 600,
            height: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${count(StudyCollectionBookStatus.newBook)} new books\n${count(StudyCollectionBookStatus.update)} updates available\n${count(StudyCollectionBookStatus.current)} already current${count(StudyCollectionBookStatus.needsAttention) == 0 ? '' : '\n${count(StudyCollectionBookStatus.needsAttention)} need attention'}',
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by title or author',
                  ),
                  onChanged: (value) =>
                      setState(() => query = value.trim().toLowerCase()),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(
                        () => selected.addAll(
                          selectable.map((book) => book.workId),
                        ),
                      ),
                      child: const Text('Select All'),
                    ),
                    TextButton(
                      onPressed: () => setState(selected.clear),
                      child: const Text('Clear All'),
                    ),
                    const Spacer(),
                    Text('${selected.length} selected'),
                  ],
                ),
                Expanded(
                  child: ListView(
                    children: visible
                        .map(
                          (book) => CheckboxListTile(
                            value: selected.contains(book.workId),
                            title: Text(book.title),
                            subtitle: Text(book.author),
                            secondary: Text(
                              book.status == StudyCollectionBookStatus.newBook
                                  ? 'New'
                                  : 'Update',
                            ),
                            onChanged: (value) => setState(
                              () => value == true
                                  ? selected.add(book.workId)
                                  : selected.remove(book.workId),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, Set.unmodifiable(selected)),
              child: Text('Import Selected (${selected.length})'),
            ),
          ],
        );
      },
    ),
  );
}
