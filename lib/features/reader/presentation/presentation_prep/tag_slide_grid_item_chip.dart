import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../data/tags/unified_tag_models.dart';
import 'tag_presentation_prep_models.dart';

class TagSlideGridItemChip extends StatelessWidget {
  const TagSlideGridItemChip({
    super.key,
    required this.item,
    required this.dragData,
    this.mediaRootPath,
    this.selected = false,
    this.showRemoveButton = false,
    this.longPressDrag = false,
    this.onTap,
    this.onRemove,
  });

  final UnifiedTagChainItem item;
  final TagPresentationCardDragData? dragData;
  final String? mediaRootPath;
  final bool selected;
  final bool showRemoveButton;
  final bool longPressDrag;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final body = _GridItemBody(
      item: item,
      mediaRootPath: mediaRootPath,
      selected: selected,
      showRemoveButton: showRemoveButton,
      onTap: onTap,
      onRemove: onRemove,
    );

    final payload = dragData;
    if (payload == null) return body;

    return longPressDrag
        ? LongPressDraggable<TagPresentationCardDragData>(
            data: payload,
            hapticFeedbackOnStart: true,
            feedback: ExcludeSemantics(
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 180,
                  child: _GridItemBody(
                    item: item,
                    mediaRootPath: mediaRootPath,
                    selected: true,
                    showRemoveButton: false,
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: body),
            child: body,
          )
        : Draggable<TagPresentationCardDragData>(
            data: payload,
            feedback: ExcludeSemantics(
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 180,
                  child: _GridItemBody(
                    item: item,
                    mediaRootPath: mediaRootPath,
                    selected: true,
                    showRemoveButton: false,
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: body),
            child: body,
          );
  }
}

class _GridItemBody extends StatelessWidget {
  const _GridItemBody({
    required this.item,
    required this.mediaRootPath,
    required this.selected,
    required this.showRemoveButton,
    this.onTap,
    this.onRemove,
  });

  final UnifiedTagChainItem item;
  final String? mediaRootPath;
  final bool selected;
  final bool showRemoveButton;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _displayTitle(item);
    final subtitle = _displaySubtitle(item);
    final background = selected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.16)
        : theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.72);
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.78);

    return LayoutBuilder(
      builder: (context, constraints) {
        final veryCompact =
            constraints.maxHeight < 24 || constraints.maxWidth < 120;
        final canShowMeta =
            !veryCompact &&
            constraints.maxWidth >= 150 &&
            constraints.maxHeight >= 28;
        final canShowRemove =
            showRemoveButton &&
            onRemove != null &&
            !veryCompact &&
            constraints.maxWidth >= 145 &&
            constraints.maxHeight >= 28;

        if (veryCompact) {
          return ClipRect(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: borderColor,
                  width: selected ? 1.1 : 0.7,
                ),
              ),
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 9.5,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: selected ? 1.5 : 0,
          color: background,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: borderColor, width: selected ? 1.2 : 0.8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: veryCompact ? 6 : 8,
                vertical: veryCompact ? 1.5 : 3,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_hasMedia(item)) ...[
                    _MediaLead(item: item, mediaRootPath: mediaRootPath),
                    const SizedBox(width: 6),
                  ],
                  if (!veryCompact) ...[
                    _TypeBadge(item: item),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        fontSize: veryCompact ? 10.5 : 11.5,
                      ),
                    ),
                  ),
                  if (canShowMeta && subtitle != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontSize: 9.5,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                  if (canShowRemove) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: onRemove,
                      tooltip: 'Remove from slide',
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 22,
                        height: 22,
                      ),
                      iconSize: 14,
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.surface.withValues(
                          alpha: 0.94,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
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
    final note = item.noteText?.trim() ?? '';
    if (note.isNotEmpty) return note;
    final legacy = item.legacyTagName?.trim() ?? '';
    if (legacy.isNotEmpty) return legacy;
    return 'Untitled item';
  }

  String? _displaySubtitle(UnifiedTagChainItem item) {
    final text = item.textSnapshot?.trim() ?? '';
    if (text.isNotEmpty && text != _displayTitle(item)) {
      return _shorten(text, maxChars: 56);
    }
    final note = item.noteText?.trim() ?? '';
    if (note.isNotEmpty && note != text) {
      return _shorten(note, maxChars: 56);
    }
    return null;
  }

  String _shorten(String value, {required int maxChars}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxChars) return normalized;
    return '${normalized.substring(0, maxChars - 1).trimRight()}…';
  }
}

bool _hasMedia(UnifiedTagChainItem item) {
  // Only items whose primary purpose is to display media should show a media
  // lead. Note/bible/elibrary items may have attached media but it is always
  // expanded into separate image items by _expandPresentationItems, so the
  // parent item itself should render as its text type without a media lead.
  return item.itemType == UnifiedTagItemType.image ||
      item.itemType == UnifiedTagItemType.media;
}

class _MediaLead extends StatelessWidget {
  const _MediaLead({required this.item, required this.mediaRootPath});

  final UnifiedTagChainItem item;
  final String? mediaRootPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedPath = _resolveMediaPath(item, mediaRootPath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 42,
        height: 42,
        child: resolvedPath != null && File(resolvedPath).existsSync()
            ? Image.file(
                File(resolvedPath),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _fallback(theme, item);
                },
              )
            : _fallback(theme, item),
      ),
    );
  }

  Widget _fallback(ThemeData theme, UnifiedTagChainItem item) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.28),
      ),
      child: Icon(
        item.itemType == UnifiedTagItemType.image
            ? Icons.image_outlined
            : Icons.perm_media_outlined,
        color: theme.colorScheme.primary,
        size: 18,
      ),
    );
  }
}

String? _resolveMediaPath(UnifiedTagChainItem item, String? mediaRootPath) {
  if (item.media.isEmpty) return null;
  final relativePath = item.media.first.relativePath.trim();
  if (relativePath.isEmpty) return null;
  if (p.isAbsolute(relativePath)) return relativePath;
  final root = mediaRootPath?.trim() ?? '';
  if (root.isEmpty) return null;
  return p.join(root, relativePath);
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.item});

  final UnifiedTagChainItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        child: Text(
          item.isPresentationTitle ? 'Title' : _itemTypeLabel(item.itemType),
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 8.5,
            height: 1.0,
          ),
        ),
      ),
    );
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
