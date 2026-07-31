import 'package:flutter/material.dart';

import '../../data/tags/unified_tag_models.dart';

class TagPresentationPrepItemTile extends StatelessWidget {
  const TagPresentationPrepItemTile({
    super.key,
    required this.item,
    this.orderLabel,
    this.assignedSlideNumber,
    this.selected = false,
    this.compact = false,
    this.onTap,
  });

  final UnifiedTagChainItem item;
  final int? orderLabel;
  final int? assignedSlideNumber;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _displayTitle(item);
    final subtitle = _displaySubtitle(item, compact: compact);
    final slideLabel = assignedSlideNumber == null
        ? null
        : 'Slide ${assignedSlideNumber!}';
    final leadingRadius = compact ? 12.0 : 14.0;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: selected ? 1 : 0,
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.24)
          : null,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 1.5 : 0.8,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 10 : 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: leadingRadius,
                child: Text(
                  (orderLabel ?? item.sortOrder).toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (compact && slideLabel != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        slideLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  _Pill(label: _itemTypeLabel(item.itemType)),
                  if (slideLabel != null && !compact) _Pill(label: slideLabel),
                  if (item.hasMedia) const _Pill(label: 'media'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _displayTitle(UnifiedTagChainItem item) {
    final title = item.displayTitle?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final snapshot = item.textSnapshot?.trim() ?? '';
    if (snapshot.isNotEmpty) return snapshot;
    if (item.legacyTagName?.trim().isNotEmpty == true) {
      return item.legacyTagName!.trim();
    }
    return 'Untitled item';
  }

  String? _displaySubtitle(UnifiedTagChainItem item, {required bool compact}) {
    final text = item.textSnapshot?.trim() ?? '';
    if (text.isNotEmpty && text != _displayTitle(item)) {
      return _shorten(text, maxChars: compact ? 72 : 140);
    }
    final note = item.noteText?.trim() ?? '';
    if (note.isNotEmpty && note != text) {
      return _shorten(note, maxChars: compact ? 72 : 140);
    }
    if (item.legacyTagName?.trim().isNotEmpty == true) {
      return 'Legacy source: ${item.legacyTagName!.trim()}';
    }
    return null;
  }

  String _shorten(String text, {required int maxChars}) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxChars) return normalized;
    return '${normalized.substring(0, maxChars - 1).trimRight()}…';
  }

  String _itemTypeLabel(UnifiedTagItemType itemType) {
    return switch (itemType) {
      UnifiedTagItemType.bibleVerse => 'Verse',
      UnifiedTagItemType.bibleRange => 'Range',
      UnifiedTagItemType.eLibraryRange => 'eLibrary',
      UnifiedTagItemType.note => 'Note',
      UnifiedTagItemType.image => 'Image',
      UnifiedTagItemType.media => 'Media',
      UnifiedTagItemType.heading => 'Heading',
      UnifiedTagItemType.unknownLegacy => 'Legacy',
    };
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
