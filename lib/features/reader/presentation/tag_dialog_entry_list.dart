import 'package:flutter/material.dart';

import 'tag_dialog_styles.dart';
import 'tag_quick_apply_helper.dart';

class TagDialogEntryList extends StatelessWidget {
  const TagDialogEntryList({
    super.key,
    required this.currentTag,
    required this.entries,
    required this.formatEntry,
    this.onEntryTap,
  });

  final String currentTag;
  final List<HashTagEntry> entries;
  final String Function(HashTagEntry entry) formatEntry;
  final ValueChanged<HashTagEntry>? onEntryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          currentTag.isEmpty ? 'Selected tag entries' : currentTag,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: TagDialogStyles.title(theme),
          ),
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('No entries for the selected tag.'),
          )
        else
          ...entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 0,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: TagDialogStyles.card(theme),
                title: Text(
                  formatEntry(entry),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: TagDialogStyles.title(theme),
                  ),
                ),
                subtitle: Text(
                  entry.verseRef,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: TagDialogStyles.body(theme),
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: TagDialogStyles.body(theme),
                ),
                onTap: onEntryTap == null ? null : () => onEntryTap!(entry),
              ),
            ),
          ),
      ],
    );
  }
}
