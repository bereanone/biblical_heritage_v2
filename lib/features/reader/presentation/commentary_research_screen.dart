import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import '../../library/data/library_catalog_service.dart';
import '../../library/presentation/library_book_reader_screen.dart';
import '../data/commentary_research_library_service.dart';
import '../data/commentary_research_filters.dart';

enum _ReaderMode { commentary, research }

const bool _debugCommentaryResearchLogs = false;

class CommentaryResearchScreen extends StatefulWidget {
  const CommentaryResearchScreen({
    super.key,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.bookName,
    required this.fontScale,
  });

  final int bookId;
  final int chapter;
  final int verse;
  final String bookName;
  final double fontScale;

  @override
  State<CommentaryResearchScreen> createState() =>
      _CommentaryResearchScreenState();
}

class _CommentaryResearchScreenState extends State<CommentaryResearchScreen> {
  final _service = CommentaryResearchLibraryService.instance;
  _ReaderMode _mode = _ReaderMode.commentary;
  bool _loading = true;
  CommentaryResearchPassageData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_debugCommentaryResearchLogs) {
      debugPrint(
        '[CommentaryResearch] load mode=${_mode.name} '
        'bookId=${widget.bookId} ref=${widget.bookName} '
        '${widget.chapter}:${widget.verse} refresh=$refresh',
      );
    }
    setState(() => _loading = true);
    final data = await _service.loadPassage(
      bookId: widget.bookId,
      chapter: widget.chapter,
      verse: widget.verse,
      bookName: widget.bookName,
      refresh: refresh,
    );
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
    if (_debugCommentaryResearchLogs) {
      debugPrint(
        '[CommentaryResearch] loaded commentary=${data.commentary.matchCount} '
        'research=${data.research.matchCount}',
      );
    }
  }

  String _passageTitle({required bool includeVerse}) {
    final bookName = _data?.bookName ?? widget.bookName;
    if (!includeVerse || widget.verse <= 0) {
      return '$bookName ${widget.chapter}';
    }
    return '$bookName ${widget.chapter}:${widget.verse}';
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scale = widget.fontScale.clamp(0.85, 2.4);
    final isCommentary = _mode == _ReaderMode.commentary;
    final passageTitle = _passageTitle(includeVerse: !isCommentary);
    final appBarTitle =
        '${isCommentary ? 'Commentary' : 'Research'}: $passageTitle';
    final segmentSelectedColor = const Color(0xFFF6D2C1);
    final segmentBorderColor = scheme.outlineVariant.withValues(alpha: 0.95);
    final activeSection = isCommentary ? data?.commentary : data?.research;
    final needsRefresh =
        activeSection?.statusMessage == 'Library index needs refresh.';

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        title: Text(
          appBarTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: ((theme.textTheme.titleLarge?.fontSize ?? 20) * scale)
                .clamp(18.0, 28.0),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_ReaderMode>(
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  ),
                  side: WidgetStateProperty.all(
                    BorderSide(color: segmentBorderColor),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return segmentSelectedColor;
                    }
                    return theme.scaffoldBackgroundColor;
                  }),
                  foregroundColor: WidgetStateProperty.all(scheme.onSurface),
                  iconColor: WidgetStateProperty.all(scheme.onSurface),
                ),
                segments: const [
                  ButtonSegment<_ReaderMode>(
                    value: _ReaderMode.commentary,
                    icon: Icon(Icons.menu_book_outlined, size: 18),
                    label: Text('Commentary'),
                  ),
                  ButtonSegment<_ReaderMode>(
                    value: _ReaderMode.research,
                    icon: Icon(Icons.search, size: 18),
                    label: Text('Research'),
                  ),
                ],
                selected: <_ReaderMode>{_mode},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  final mode = selection.first;
                  if (mode == _mode) return;
                  if (_debugCommentaryResearchLogs) {
                    debugPrint(
                      '[CommentaryResearch] tab ${_mode.name} -> ${mode.name} '
                      'bookId=${widget.bookId} ref=${widget.bookName} '
                      '${widget.chapter}:${widget.verse}',
                    );
                  }
                  setState(() => _mode = mode);
                },
              ),
            ),
            const SizedBox(height: 12),
            if (needsRefresh) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Library index needs refresh',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      FilledButton(
                        onPressed: _loading ? null : () => _load(refresh: true),
                        child: const Text('Refresh Library Index'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            'Loading passage...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : data == null
                  ? const SizedBox.shrink()
                  : isCommentary
                  ? _CommentaryBody(data: data, fontScale: scale)
                  : _ResearchBody(
                      data: data,
                      passageTitle: passageTitle,
                      fontScale: scale,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentaryBody extends StatelessWidget {
  const _CommentaryBody({required this.data, required this.fontScale});

  final CommentaryResearchPassageData data;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final section = data.commentary;
    final scale = fontScale.clamp(0.85, 2.4);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: ((theme.textTheme.titleMedium?.fontSize ?? 16) * scale).clamp(
        15.0,
        30.0,
      ),
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
    );
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: ((theme.textTheme.bodySmall?.fontSize ?? 12) * scale).clamp(
        11.0,
        24.0,
      ),
      color: scheme.onSurfaceVariant,
    );

    return ListView(
      children: [
        Text(_sectionSourceTitle(section), style: titleStyle),
        const SizedBox(height: 4),
        Text(
          '${section.matchCount} indexed EPUB commentary entries from ${_sectionSourceCode(section)}',
          style: bodyStyle,
        ),
        const SizedBox(height: 12),
        if (section.matches.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('No commentary source is installed yet for this book.'),
          )
        else
          ..._commentaryGroups(context, section.matches, fontScale),
      ],
    );
  }
}

class _ResearchBody extends StatelessWidget {
  const _ResearchBody({
    required this.data,
    required this.passageTitle,
    required this.fontScale,
  });

  final CommentaryResearchPassageData data;
  final String passageTitle;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final section = data.research;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scale = fontScale.clamp(0.85, 2.4);
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: ((theme.textTheme.bodySmall?.fontSize ?? 12) * scale).clamp(
        11.0,
        24.0,
      ),
      color: scheme.onSurfaceVariant,
    );

    return ListView(
      children: [
        Text(
          '${section.matchCount} EPUB research hits across the library for $passageTitle',
          style: bodyStyle,
        ),
        const SizedBox(height: 12),
        if (section.matches.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'No research hits found yet in the research library for this reference.',
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final match in section.matches)
            _ResearchHitCard(
              match: match,
              fontScale: fontScale,
              onOpenEpub: () => _openEpubSource(context, match),
            ),
      ],
    );
  }
}

List<Widget> _commentaryGroups(
  BuildContext context,
  List<CommentaryResearchMatchItem> matches,
  double fontScale,
) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final grouped = <String, List<CommentaryResearchMatchItem>>{};
  for (final match in matches) {
    final key = '${match.verseStart}:${match.verseEnd}';
    grouped.putIfAbsent(key, () => <CommentaryResearchMatchItem>[]).add(match);
  }

  final keys = grouped.keys.toList(growable: false)
    ..sort((a, b) {
      final aParts = a.split(':');
      final bParts = b.split(':');
      final aStart = int.tryParse(aParts.first) ?? 0;
      final bStart = int.tryParse(bParts.first) ?? 0;
      final startCmp = aStart.compareTo(bStart);
      if (startCmp != 0) return startCmp;
      final aEnd = int.tryParse(aParts.last) ?? 0;
      final bEnd = int.tryParse(bParts.last) ?? 0;
      return aEnd.compareTo(bEnd);
    });

  return [
    for (final key in keys)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _verseLabel(key),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize:
                        ((theme.textTheme.headlineSmall?.fontSize ?? 20) *
                                fontScale)
                            .clamp(18.0, 30.0),
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: grouped[key]!
                    .map(
                      (match) => _CommentaryLegacyCard(
                        match: match,
                        fontScale: fontScale,
                        onOpenEpub: () => _openEpubSource(context, match),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
  ];
}

String _verseLabel(String key) {
  final parts = key.split(':');
  if (parts.length != 2) return key;
  return parts.first == parts.last
      ? parts.first
      : '${parts.first}–${parts.last}';
}

class _ResearchHitCard extends StatelessWidget {
  const _ResearchHitCard({
    required this.match,
    required this.fontScale,
    required this.onOpenEpub,
  });

  final CommentaryResearchMatchItem match;
  final double fontScale;
  final VoidCallback onOpenEpub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scale = fontScale.clamp(0.85, 2.4);
    final cardBackground = theme.brightness == Brightness.dark
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerLow;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: ((theme.textTheme.titleMedium?.fontSize ?? 16) * scale).clamp(
        15.0,
        24.0,
      ),
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
    );
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: ((theme.textTheme.bodyMedium?.fontSize ?? 14) * scale).clamp(
        13.0,
        24.0,
      ),
      color: scheme.onSurface,
      height: 1.45,
    );
    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: ((theme.textTheme.bodySmall?.fontSize ?? 12) * scale).clamp(
        11.0,
        18.0,
      ),
      color: scheme.onSurfaceVariant,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: cardBackground,
      shadowColor: scheme.shadow.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(match.itemTitle, style: titleStyle)),
                Tooltip(
                  message: 'Open source EPUB',
                  child: Semantics(
                    button: true,
                    label: 'Open source EPUB',
                    child: InkWell(
                      onTap: onOpenEpub,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6D2C1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'EPUB',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              CommentaryResearchFilters.commentaryDisplayText(match),
              style: bodyStyle,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${match.originalReferenceText} · ${match.itemTitle}',
                style: metaStyle?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentaryLegacyCard extends StatelessWidget {
  const _CommentaryLegacyCard({
    required this.match,
    required this.fontScale,
    required this.onOpenEpub,
  });

  final CommentaryResearchMatchItem match;
  final double fontScale;
  final VoidCallback onOpenEpub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scale = fontScale.clamp(0.85, 2.4);
    final cardBackground = theme.brightness == Brightness.dark
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerLow;
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: ((theme.textTheme.bodyLarge?.fontSize ?? 16) * scale).clamp(
        14.0,
        28.0,
      ),
      height: 1.45,
      color: scheme.onSurface,
    );
    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: ((theme.textTheme.bodySmall?.fontSize ?? 12) * scale).clamp(
        11.0,
        18.0,
      ),
      fontStyle: FontStyle.italic,
      color: scheme.onSurfaceVariant,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardBackground,
      shadowColor: scheme.shadow.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    CommentaryResearchFilters.commentaryDisplayText(match),
                    style: bodyStyle,
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Open source EPUB',
                  child: Semantics(
                    button: true,
                    label: 'Open source EPUB',
                    child: InkWell(
                      onTap: onOpenEpub,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6D2C1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'EPUB',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text(_citationLabel(match), style: metaStyle),
            ),
          ],
        ),
      ),
    );
  }

  String _citationLabel(CommentaryResearchMatchItem match) {
    final volume = RegExp(
      r'(\dABC|\dBC)',
      caseSensitive: false,
    ).firstMatch(match.fileName);
    return volume?.group(1)?.toUpperCase() ?? match.fileName;
  }
}

Future<void> _openEpubSource(
  BuildContext context,
  CommentaryResearchMatchItem match,
) async {
  final selection = await LibraryRootService.instance.loadSelection();
  final rootPath = selection.exists
      ? selection.path?.trim() ?? ''
      : (await LibraryRootService.instance.accessibleLibraryRootPath())
                ?.trim() ??
            '';
  if (!context.mounted) return;

  if (rootPath.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Source EPUB location is not available for this result.'),
        duration: Duration(milliseconds: 1800),
      ),
    );
    return;
  }

  final sourceTarget = await _resolveSourceEpubTarget(match);
  if (!context.mounted) return;

  if (sourceTarget == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Source EPUB location is not available for this result.'),
        duration: Duration(milliseconds: 1800),
      ),
    );
    return;
  }

  final resolvedFilePath = p.join(rootPath, sourceTarget.item.relativePath);
  if (!File(resolvedFilePath).existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Source EPUB location is not available for this result.'),
        duration: Duration(milliseconds: 1800),
      ),
    );
    return;
  }

  final metadata = <String>[
    if ((match.epubCfi ?? '').trim().isNotEmpty) 'epub_cfi',
    if ((sourceTarget.initialHref ?? '').trim().isNotEmpty) 'epub_href',
    if ((sourceTarget.initialAnchorId ?? '').trim().isNotEmpty) 'anchor_id',
    if (sourceTarget.initialSpineIndex != null) 'spine_index',
    if (sourceTarget.initialParagraphIndex != null) 'paragraph_index',
  ];
  if (_debugCommentaryResearchLogs) {
    debugPrint(
      '[CommentaryResearch] EPUB badge tapped '
      'itemTitle=${match.itemTitle} '
      'libraryItemId=${sourceTarget.item.id} '
      'relativePath=${sourceTarget.item.relativePath} '
      'resolvedFilePath=$resolvedFilePath '
      'availableJumpMetadata=${metadata.isEmpty ? 'none' : metadata.join(', ')}',
    );
  }

  try {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryBookReaderScreen(
          item: sourceTarget.item,
          initialHref: sourceTarget.initialHref,
          initialAnchorId: sourceTarget.initialAnchorId,
          initialSpineIndex: sourceTarget.initialSpineIndex,
          initialParagraphIndex: sourceTarget.initialParagraphIndex,
        ),
      ),
    );
  } catch (error) {
    if (_debugCommentaryResearchLogs) {
      debugPrint('[CommentaryResearch] EPUB launch failed error=$error');
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open the eLibrary reader: $error'),
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }
}

Future<_ResolvedSourceEpubTarget?> _resolveSourceEpubTarget(
  CommentaryResearchMatchItem match,
) async {
  final service = LibraryCatalogService.instance;
  LibraryCatalogItem? item;

  final libraryItemId = match.libraryItemId.trim();
  if (libraryItemId.isNotEmpty) {
    item = await service.loadItemById(libraryItemId);
  }

  final relativePath = match.relativePath.trim();
  if (item == null && relativePath.isNotEmpty) {
    item = await service.loadItemByRelativePath(relativePath);
  }

  if (item == null) {
    final candidates = await service.findItemsByTitle(
      title: match.itemTitle,
      limit: 2,
    );
    if (candidates.length == 1) {
      item = candidates.first;
    } else if (candidates.length > 1) {
      if (_debugCommentaryResearchLogs) {
        debugPrint(
          '[CommentaryResearch] EPUB source lookup ambiguous '
          'title=${match.itemTitle} '
          'candidates=${candidates.map((candidate) => candidate.id).join(', ')}',
        );
      }
      return null;
    }
  }

  if (item == null) {
    if (_debugCommentaryResearchLogs) {
      debugPrint(
        '[CommentaryResearch] EPUB source lookup failed '
        'libraryItemId=${match.libraryItemId} '
        'relativePath=${match.relativePath} '
        'title=${match.itemTitle}',
      );
    }
    return null;
  }

  final hrefParts = _splitEpubHref(match.epubHref);
  final itemHrefParts = _splitEpubHref(item.epubHref);
  final initialHref =
      hrefParts.href ??
      itemHrefParts.href ??
      (match.epubHref?.trim().isNotEmpty == true
          ? match.epubHref!.trim()
          : null);
  final initialAnchorId =
      hrefParts.anchor ??
      _trimToNull(match.anchorId) ??
      itemHrefParts.anchor ??
      _trimToNull(item.anchorId);
  final initialSpineIndex = match.spineIndex ?? item.spineIndex;
  final initialParagraphIndex = match.paragraphIndex ?? item.paragraphIndex;

  return _ResolvedSourceEpubTarget(
    item: item,
    initialHref: _trimToNull(initialHref),
    initialAnchorId: initialAnchorId,
    initialSpineIndex: initialSpineIndex,
    initialParagraphIndex: initialParagraphIndex,
  );
}

({String? href, String? anchor}) _splitEpubHref(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return (href: null, anchor: null);
  }
  final parts = trimmed.split('#');
  final href = parts.first.trim();
  final anchor = parts.length > 1 ? parts.skip(1).join('#').trim() : '';
  return (
    href: href.isEmpty ? null : href,
    anchor: anchor.isEmpty ? null : anchor,
  );
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

class _ResolvedSourceEpubTarget {
  const _ResolvedSourceEpubTarget({
    required this.item,
    required this.initialHref,
    required this.initialAnchorId,
    required this.initialSpineIndex,
    required this.initialParagraphIndex,
  });

  final LibraryCatalogItem item;
  final String? initialHref;
  final String? initialAnchorId;
  final int? initialSpineIndex;
  final int? initialParagraphIndex;
}

String _sectionSourceTitle(CommentaryResearchSectionData section) {
  if (section.matches.isNotEmpty) {
    return section.matches.first.itemTitle;
  }
  if (section.files.isNotEmpty) {
    return section.files.first.title;
  }
  return section.title;
}

String _sectionSourceCode(CommentaryResearchSectionData section) {
  if (section.matches.isNotEmpty) {
    return _volumeCodeFromName(section.matches.first.fileName) ??
        section.matches.first.fileName;
  }
  if (section.files.isNotEmpty) {
    return _volumeCodeFromName(section.files.first.fileName) ??
        section.files.first.fileName;
  }
  return section.title;
}

String? _volumeCodeFromName(String value) {
  final match = RegExp(r'(\dABC|\dBC)', caseSensitive: false).firstMatch(value);
  return match?.group(1)?.toUpperCase();
}
