import 'package:flutter/material.dart';

import '../../data/tags/unified_tag_models.dart';
import 'tag_presentation_prep_models.dart';

class TagDraggableSlideCard extends StatelessWidget {
  const TagDraggableSlideCard({
    super.key,
    required this.item,
    required this.dragData,
    this.compact = false,
    this.selected = false,
    this.showRemoveButton = false,
    this.longPressDrag = false,
    this.onTap,
    this.onRemove,
  });

  final UnifiedTagChainItem item;
  final TagPresentationCardDragData? dragData;
  final bool compact;
  final bool selected;
  final bool showRemoveButton;
  final bool longPressDrag;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final card = _SlideCardBody(
      item: item,
      compact: compact,
      selected: selected,
      showRemoveButton: showRemoveButton,
      onTap: onTap,
      onRemove: onRemove,
    );

    final dragPayload = dragData;
    if (dragPayload == null) {
      return card;
    }

    final draggable = longPressDrag
        ? LongPressDraggable<TagPresentationCardDragData>(
            data: dragPayload,
            hapticFeedbackOnStart: true,
            feedback: ExcludeSemantics(
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: compact ? 220 : 260,
                  child: _SlideCardBody(
                    item: item,
                    compact: compact,
                    selected: true,
                    showRemoveButton: false,
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: card),
            child: card,
          )
        : Draggable<TagPresentationCardDragData>(
            data: dragPayload,
            feedback: ExcludeSemantics(
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: compact ? 220 : 260,
                  child: _SlideCardBody(
                    item: item,
                    compact: compact,
                    selected: true,
                    showRemoveButton: false,
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: card),
            child: card,
          );

    return draggable;
  }
}

class _SlideCardBody extends StatelessWidget {
  const _SlideCardBody({
    required this.item,
    required this.compact,
    required this.selected,
    required this.showRemoveButton,
    this.onTap,
    this.onRemove,
  });

  final UnifiedTagChainItem item;
  final bool compact;
  final bool selected;
  final bool showRemoveButton;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final title = _displayTitle(item);
        final subtitle = _displaySubtitle(item, compact: compact);
        final background = selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.18)
            : theme.colorScheme.surfaceContainerLowest;
        final borderColor = selected
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant;
        final veryCompact =
            compact || constraints.maxHeight < 72 || constraints.maxWidth < 190;

        if (veryCompact) {
          return ClipRect(
            child: Card(
              clipBehavior: Clip.antiAlias,
              elevation: selected ? 1 : 0,
              color: background,
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: borderColor,
                  width: selected ? 1.2 : 0.8,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      _TinyBadge(label: _itemTypeLabel(item.itemType)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: selected ? 2 : 0,
          color: background,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: borderColor, width: selected ? 1.5 : 0.8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 10 : 12,
                    compact ? 10 : 12,
                    compact ? 10 : 12,
                    compact ? 10 : 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: compact ? 12 : 14,
                        child: Text(
                          _itemTypeLabel(item.itemType),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
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
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _Pill(label: _itemTypeLabel(item.itemType)),
                                if (item.hasMedia) const _Pill(label: 'media'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (showRemoveButton && onRemove != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: 'Remove from slide',
                      onPressed: onRemove,
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.surface.withValues(
                          alpha: 0.95,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _displayTitle(UnifiedTagChainItem item) {
    final title = item.displayTitle?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final snapshot = item.textSnapshot?.trim() ?? '';
    if (snapshot.isNotEmpty) return snapshot;
    final legacy = item.legacyTagName?.trim() ?? '';
    if (legacy.isNotEmpty) return legacy;
    return 'Untitled item';
  }

  String? _displaySubtitle(UnifiedTagChainItem item, {required bool compact}) {
    final text = item.textSnapshot?.trim() ?? '';
    if (text.isNotEmpty && text != _displayTitle(item)) {
      return _shorten(text, maxChars: compact ? 72 : 120);
    }
    final note = item.noteText?.trim() ?? '';
    if (note.isNotEmpty && note != text) {
      return _shorten(note, maxChars: compact ? 72 : 120);
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

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 8.5,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
