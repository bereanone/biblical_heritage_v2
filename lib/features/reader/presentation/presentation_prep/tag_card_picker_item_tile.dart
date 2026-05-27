import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../core/database/study_bible_database.dart';
import '../../data/tags/unified_tag_models.dart';
import 'tag_presentation_media_path_resolver.dart';

class TagCardPickerItemTile extends StatefulWidget {
  const TagCardPickerItemTile({
    super.key,
    required this.item,
    required this.onTap,
    this.mediaRootPath,
  });

  final UnifiedTagChainItem item;
  final VoidCallback onTap;
  final String? mediaRootPath;

  @override
  State<TagCardPickerItemTile> createState() => _TagCardPickerItemTileState();
}

class _TagCardPickerItemTileState extends State<TagCardPickerItemTile> {
  late Future<_PickerPreviewData> _previewFuture;
  late Future<List<String>> _mediaRootsFuture;

  @override
  void initState() {
    super.initState();
    _previewFuture = _resolvePreviewData();
    _mediaRootsFuture = _resolveMediaRoots();
  }

  @override
  void didUpdateWidget(covariant TagCardPickerItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.mediaRootPath != widget.mediaRootPath) {
      _previewFuture = _resolvePreviewData();
      _mediaRootsFuture = _resolveMediaRoots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final mediaSource = _resolveMediaSource(item);
    final title = _displayTitle(item, mediaSource: mediaSource);
    final typeLabel = _typeLabel(item.itemType);
    final hasMedia =
        mediaSource != null ||
        item.hasMedia ||
        item.itemType == UnifiedTagItemType.image ||
        item.itemType == UnifiedTagItemType.media;
    final secondaryLabel = _secondaryLabel(item, mediaSource: mediaSource);
    final mediaCount = item.media.isNotEmpty
        ? item.media.length
        : mediaSource != null
        ? 1
        : 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: _buildLead(context, hasMedia: hasMedia)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _Chip(label: typeLabel),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (hasMedia)
                          _Chip(
                            label: mediaCount > 1
                                ? '$mediaCount media'
                                : 'Media',
                          ),
                        if (secondaryLabel.isNotEmpty)
                          _Chip(label: secondaryLabel),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<_PickerPreviewData>(
                      future: _previewFuture,
                      builder: (context, snapshot) {
                        final preview =
                            snapshot.data ??
                            _fallbackPreviewData(
                              item,
                              mediaSource: mediaSource,
                            );
                        final children = <Widget>[];

                        if (preview.reference != null &&
                            preview.reference!.isNotEmpty) {
                          children.add(
                            Text(
                              preview.reference!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }

                        if (preview.body != null && preview.body!.isNotEmpty) {
                          if (children.isNotEmpty) {
                            children.add(const SizedBox(height: 6));
                          }
                          children.add(
                            Text(
                              preview.body!,
                              maxLines: hasMedia ? 4 : 5,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.25,
                              ),
                            ),
                          );
                        }

                        if (preview.secondary != null &&
                            preview.secondary!.isNotEmpty) {
                          if (children.isNotEmpty) {
                            children.add(const SizedBox(height: 6));
                          }
                          children.add(
                            Text(
                              preview.secondary!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                                height: 1.2,
                              ),
                            ),
                          );
                        }

                        if (children.isEmpty) {
                          children.add(
                            Text(
                              'Loading preview…',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: children,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLead(BuildContext context, {required bool hasMedia}) {
    final theme = Theme.of(context);
    final mediaSource = _resolveMediaSource(widget.item);
    if (hasMedia) {
      return _MediaPreview(
        item: widget.item,
        mediaSource: mediaSource,
        mediaRootsFuture: _mediaRootsFuture,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        width: 76,
        height: 76,
        child: Icon(
          _leadingIcon(widget.item),
          color: theme.colorScheme.primary,
          size: 28,
        ),
      ),
    );
  }

  Future<_PickerPreviewData> _resolvePreviewData() async {
    final item = widget.item;
    final mediaSource = _resolveMediaSource(item);
    switch (item.itemType) {
      case UnifiedTagItemType.bibleVerse:
      case UnifiedTagItemType.bibleRange:
        return _PickerPreviewData(
          reference: _displayTitle(item, mediaSource: mediaSource),
          body: await _loadBibleText(item.bibleAnchor) ?? _fallbackBody(item),
          secondary: _cleanText(item.noteText) ?? _cleanText(item.htmlContent),
        );
      case UnifiedTagItemType.eLibraryRange:
        return _PickerPreviewData(
          reference: _eLibraryReference(item),
          body: _eLibraryBody(item),
          secondary: _cleanText(item.noteText),
        );
      case UnifiedTagItemType.note:
        return _PickerPreviewData(
          reference: _noteTitle(item),
          body: _noteBody(item),
          secondary:
              _cleanText(item.textSnapshot) ??
              _mediaSourceLabel(mediaSource) ??
              _cleanText(item.htmlContent),
        );
      case UnifiedTagItemType.image:
      case UnifiedTagItemType.media:
        return _PickerPreviewData(
          reference: _mediaTitle(item, mediaSource: mediaSource),
          body: _mediaBody(item, mediaSource: mediaSource),
          secondary: _mediaSecondary(item, mediaSource: mediaSource),
        );
      case UnifiedTagItemType.heading:
        return _PickerPreviewData(
          reference: _displayTitle(item, mediaSource: mediaSource),
          body: _fallbackBody(item),
          secondary: _cleanText(item.noteText),
        );
      case UnifiedTagItemType.unknownLegacy:
        return _PickerPreviewData(
          reference: _displayTitle(item, mediaSource: mediaSource),
          body: _fallbackBody(item),
          secondary: _cleanText(item.noteText),
        );
    }
  }

  Future<List<String>> _resolveMediaRoots() {
    return TagPresentationMediaPathResolver.collectRootCandidates(
      preferredRootPath: widget.mediaRootPath,
    );
  }

  _PickerPreviewData _fallbackPreviewData(
    UnifiedTagChainItem item, {
    _PickerMediaSource? mediaSource,
  }) {
    return _PickerPreviewData(
      reference: _displayTitle(item, mediaSource: mediaSource),
      body: _fallbackBody(item),
      secondary: _secondaryLabel(item, mediaSource: mediaSource),
    );
  }

  Future<String?> _loadBibleText(UnifiedTagBibleAnchor? anchor) async {
    if (anchor == null) return null;
    final start = anchor.verseStart;
    final end = anchor.verseEnd < start ? start : anchor.verseEnd;
    if (start <= 0 || end <= 0) return null;

    final verses = <String>[];
    for (var verse = start; verse <= end; verse++) {
      final text = await StudyBibleDatabase.instance.loadVerseText(
        bookNumber: anchor.bookNumber,
        chapter: anchor.chapter,
        verse: verse,
      );
      final cleaned = _cleanText(text);
      if (cleaned != null && cleaned.isNotEmpty) {
        verses.add(cleaned);
      }
    }
    if (verses.isEmpty) return null;
    return verses.join(' ');
  }

  String _leadingIconLabel(UnifiedTagChainItem item) {
    return switch (item.itemType) {
      UnifiedTagItemType.image => 'Image',
      UnifiedTagItemType.media => 'Media',
      _ => 'Item',
    };
  }

  IconData _leadingIcon(UnifiedTagChainItem item) {
    return switch (item.itemType) {
      UnifiedTagItemType.bibleVerse ||
      UnifiedTagItemType.bibleRange => Icons.auto_stories_outlined,
      UnifiedTagItemType.eLibraryRange => Icons.menu_book_outlined,
      UnifiedTagItemType.note => Icons.note_outlined,
      UnifiedTagItemType.image => Icons.image_outlined,
      UnifiedTagItemType.media => Icons.perm_media_outlined,
      UnifiedTagItemType.heading => Icons.title_outlined,
      UnifiedTagItemType.unknownLegacy => Icons.layers_outlined,
    };
  }

  String _displayTitle(
    UnifiedTagChainItem item, {
    _PickerMediaSource? mediaSource,
  }) {
    final title = item.displayTitle?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final bible = item.bibleAnchor;
    if (bible != null) {
      final verseRef = bible.verseRef?.trim() ?? '';
      if (verseRef.isNotEmpty) return verseRef;
      final referenceCode = bible.referenceCode?.trim() ?? '';
      if (referenceCode.isNotEmpty) return referenceCode;
    }
    final elibrary = item.elibraryAnchor;
    if (elibrary != null) {
      final sourceTitle = elibrary.sourceTitle?.trim() ?? '';
      if (sourceTitle.isNotEmpty) return sourceTitle;
      final sourceRef = elibrary.sourceReferenceText?.trim() ?? '';
      if (sourceRef.isNotEmpty) return sourceRef;
      if (elibrary.compactRef.trim().isNotEmpty) return elibrary.compactRef;
    }
    final noteTitle = _noteTitle(item);
    if (noteTitle.isNotEmpty) return noteTitle;
    final media = mediaSource ?? _resolveMediaSource(item);
    if (media != null) {
      final label = _mediaSourceLabel(media);
      if (label != null && label.isNotEmpty) return label;
      return _leadingIconLabel(item);
    }
    final snapshot = item.textSnapshot?.trim() ?? '';
    if (snapshot.isNotEmpty) return _cleanPlain(snapshot) ?? snapshot;
    return _leadingIconLabel(item);
  }

  String? _fallbackBody(UnifiedTagChainItem item) {
    final snapshot = _cleanPlain(item.textSnapshot);
    if (snapshot != null) return snapshot;
    final note = _cleanPlain(item.noteText);
    if (note != null) return note;
    final html = _cleanPlain(item.htmlContent);
    if (html != null) return _stripHtml(html);
    final media = _mediaBody(item, mediaSource: _resolveMediaSource(item));
    if (media.trim().isNotEmpty) return media;
    return null;
  }

  String _noteTitle(UnifiedTagChainItem item) {
    final raw = item.rawFields;
    final candidates = <String?>[
      _cleanPlain(raw['note_title']?.toString()),
      _cleanPlain(raw['user_title']?.toString()),
      _cleanPlain(raw['title']?.toString()),
      _cleanPlain(raw['source_title']?.toString()),
      _cleanPlain(raw['source_work_title']?.toString()),
      _cleanPlain(item.displayTitle),
    ];
    for (final candidate in candidates) {
      if (candidate != null && candidate.isNotEmpty && candidate != 'Note') {
        return candidate;
      }
    }
    return 'Note';
  }

  String _noteBody(UnifiedTagChainItem item) {
    final note = _cleanPlain(item.noteText);
    if (note != null) return note;
    final snapshot = _cleanPlain(item.textSnapshot);
    if (snapshot != null) return snapshot;
    final html = _cleanPlain(item.htmlContent);
    if (html != null) return _stripHtml(html);
    return 'No note text available.';
  }

  String _eLibraryReference(UnifiedTagChainItem item) {
    final elibrary = item.elibraryAnchor;
    if (elibrary == null) return 'eLibrary';
    final title = _cleanPlain(elibrary.sourceTitle);
    if (title != null) return title;
    final location = _cleanPlain(elibrary.sourceLocation);
    if (location != null) return location;
    final referenceText = _cleanPlain(elibrary.sourceReferenceText);
    if (referenceText != null) return referenceText;
    return elibrary.compactRef;
  }

  String _eLibraryBody(UnifiedTagChainItem item) {
    final elibrary = item.elibraryAnchor;
    if (elibrary == null) {
      return _fallbackBody(item) ?? 'eLibrary content unavailable.';
    }

    final selectedText = _cleanPlain(elibrary.selectedTextSnapshot);
    if (selectedText != null) return selectedText;
    final excerpt = _cleanPlain(elibrary.excerpt);
    if (excerpt != null) return excerpt;
    final paragraph = _cleanPlain(elibrary.sourceParagraph);
    if (paragraph != null) return paragraph;
    final snapshot = _cleanPlain(item.textSnapshot);
    if (snapshot != null) return snapshot;
    final html = _cleanPlain(item.htmlContent);
    if (html != null) return _stripHtml(html);
    return 'eLibrary content unavailable.';
  }

  String _mediaTitle(
    UnifiedTagChainItem item, {
    _PickerMediaSource? mediaSource,
  }) {
    final media = mediaSource ?? _resolveMediaSource(item);
    if (media == null) {
      return item.itemType == UnifiedTagItemType.image ? 'Image' : 'Media';
    }
    return _mediaSourceLabel(media) ??
        (item.itemType == UnifiedTagItemType.image ? 'Image' : 'Media');
  }

  String _mediaBody(
    UnifiedTagChainItem item, {
    _PickerMediaSource? mediaSource,
  }) {
    final media = mediaSource ?? _resolveMediaSource(item);
    if (media == null) {
      final note = _cleanPlain(item.noteText);
      if (note != null) return note;
      return 'Media item';
    }
    final label = _mediaSourceLabel(media);
    if (label != null) return label;
    return 'Media item';
  }

  String? _mediaSecondary(
    UnifiedTagChainItem item, {
    _PickerMediaSource? mediaSource,
  }) {
    final note = _cleanPlain(item.noteText);
    if (note != null) return note;
    final snapshot = _cleanPlain(item.textSnapshot);
    if (snapshot != null) return snapshot;
    final media = mediaSource ?? _resolveMediaSource(item);
    if (media != null) {
      final path = _cleanPlain(media.relativePath);
      if (path != null) return path;
    }
    return null;
  }

  String _secondaryLabel(
    UnifiedTagChainItem item, {
    _PickerMediaSource? mediaSource,
  }) {
    final bible = item.bibleAnchor;
    if (bible != null) {
      final verseRef = bible.verseRef?.trim() ?? '';
      if (verseRef.isNotEmpty) return verseRef;
      final referenceCode = bible.referenceCode?.trim() ?? '';
      if (referenceCode.isNotEmpty) return referenceCode;
    }
    final elibrary = item.elibraryAnchor;
    if (elibrary != null) {
      final sourceTitle = elibrary.sourceTitle?.trim() ?? '';
      if (sourceTitle.isNotEmpty) return sourceTitle;
      final sourceRef = elibrary.sourceReferenceText?.trim() ?? '';
      if (sourceRef.isNotEmpty) return sourceRef;
      return elibrary.compactRef;
    }
    final noteTitle = _noteTitle(item);
    if (noteTitle.isNotEmpty && noteTitle != 'Note') return noteTitle;
    final media = mediaSource ?? _resolveMediaSource(item);
    final mediaLabel = _mediaSourceLabel(media);
    if (mediaLabel != null) return mediaLabel;
    return '';
  }

  String _typeLabel(UnifiedTagItemType itemType) {
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

  String? _cleanPlain(String? value) {
    final cleaned = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return cleaned.isEmpty ? null : cleaned;
  }

  String _stripHtml(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? _cleanText(String? value) {
    final cleaned = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return cleaned.isEmpty ? null : cleaned;
  }

  _PickerMediaSource? _resolveMediaSource(UnifiedTagChainItem item) {
    if (item.media.isNotEmpty) {
      final first = item.media.first;
      return _PickerMediaSource(
        relativePath: first.relativePath.trim(),
        caption: _cleanText(first.caption),
        isImage: first.mediaType.toLowerCase().startsWith('image/'),
      );
    }

    final html = item.htmlContent?.trim() ?? '';
    if (html.isEmpty) return null;
    final mediaPath = _firstMediaPathFromHtml(html);
    if (mediaPath == null) return null;
    return _PickerMediaSource(
      relativePath: mediaPath,
      caption: _cleanText(item.noteText) ?? _cleanText(item.textSnapshot),
      isImage: _pathLooksLikeImage(mediaPath),
    );
  }

  String? _firstMediaPathFromHtml(String html) {
    final regex = RegExp(
      r'''(?:src|href)=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in regex.allMatches(html)) {
      final raw = match.group(1)?.trim() ?? '';
      if (raw.isEmpty || raw.startsWith('data:')) continue;
      return raw;
    }
    return null;
  }

  bool _pathLooksLikeImage(String path) {
    final ext = p.extension(path).toLowerCase();
    return const {
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.heic',
    }.contains(ext);
  }

  String? _mediaSourceLabel(_PickerMediaSource? media) {
    if (media == null) return null;
    final caption = media.caption?.trim() ?? '';
    if (caption.isNotEmpty) {
      return '${media.isImage ? 'Image' : 'Media'}: $caption';
    }
    final path = media.relativePath.trim();
    if (path.isNotEmpty) {
      return '${media.isImage ? 'Image' : 'Media'}: ${p.basename(path)}';
    }
    return media.isImage ? 'Image' : 'Media';
  }
}

class _PickerPreviewData {
  const _PickerPreviewData({
    required this.reference,
    required this.body,
    this.secondary,
  });

  final String? reference;
  final String? body;
  final String? secondary;
}

class _PickerMediaSource {
  const _PickerMediaSource({
    required this.relativePath,
    required this.isImage,
    this.caption,
  });

  final String relativePath;
  final bool isImage;
  final String? caption;
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.item,
    required this.mediaRootsFuture,
    this.mediaSource,
  });

  final UnifiedTagChainItem item;
  final Future<List<String>> mediaRootsFuture;
  final _PickerMediaSource? mediaSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = mediaSource;
    if (source == null) {
      return _placeholder(
        theme,
        item.media.isNotEmpty ? item.media.first.relativePath : '',
      );
    }

    return FutureBuilder<List<String>>(
      future: mediaRootsFuture,
      builder: (context, snapshot) {
        final roots = snapshot.data ?? const <String>[];
        final resolvedPath =
            TagPresentationMediaPathResolver.resolveStoredMediaPath(
              source.relativePath,
              roots,
            );
        return SizedBox(
          width: 76,
          height: 76,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.18,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: resolvedPath != null && File(resolvedPath).existsSync()
                  ? Image.file(
                      File(resolvedPath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _placeholder(theme, source.relativePath);
                      },
                    )
                  : _placeholder(theme, source.relativePath),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder(ThemeData theme, String relativePath) {
    final label = p.basename(relativePath.trim());
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            item.itemType == UnifiedTagItemType.image
                ? Icons.image_outlined
                : Icons.perm_media_outlined,
            color: theme.colorScheme.primary,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label.isEmpty ? 'Image unavailable' : label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.0,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

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
