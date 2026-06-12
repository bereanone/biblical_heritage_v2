import 'package:flutter/material.dart';

import '../../../../core/theme/app_settings_service.dart';
import '../../data/presentation/presentation_prep_db_models.dart';
import '../../data/presentation/presentation_prep_repository.dart';
import '../../data/tags/unified_tag_models.dart';
import 'presentation_ui_helpers.dart';
import 'tag_presentation_prep_models.dart';
import 'tag_presentation_prep_screen.dart';
import 'tag_presentation_prep_state.dart';
import 'tag_presentation_run_screen.dart';
import 'tag_presentation_slide_preview.dart';
import 'tag_slide_grid_models.dart';

class _CopiedSlideInfo {
  const _CopiedSlideInfo({
    required this.sourcePresentationId,
    required this.sourcePresentationName,
    required this.sourceSlideId,
    required this.sourceSlideNumber,
  });
  final int sourcePresentationId;
  final String sourcePresentationName;
  final int sourceSlideId;
  final int sourceSlideNumber;
}

class TagSavedPresentationsScreen extends StatefulWidget {
  const TagSavedPresentationsScreen({super.key});

  @override
  State<TagSavedPresentationsScreen> createState() =>
      _TagSavedPresentationsScreenState();
}

class _TagSavedPresentationsScreenState
    extends State<TagSavedPresentationsScreen> {
  bool _loading = true;
  double _fontScale = 1.0;
  List<PresentationGroupRecord> _presentations = const [];
  String? _error;
  _CopiedSlideInfo? _copiedSlide;
  final Set<int> _expandedIds = {};
  final Map<int, List<PresentationSlideRecord>> _slidesByPresId = {};
  final Set<int> _loadingSlideIds = {};

  @override
  void initState() {
    super.initState();
    _loadFontScale();
    _load();
  }

  Future<void> _loadFontScale() async {
    final scale = await AppSettingsService.instance.loadViewerFontScale();
    if (!mounted) return;
    setState(() => _fontScale = scale.clamp(0.8, 2.4).toDouble());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final list =
          await PresentationPrepRepository.instance.listPresentations();
      if (!mounted) return;
      setState(() {
        _presentations = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _playPresentation(PresentationGroupRecord record) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TagPresentationRunScreen(
          presentationId: record.id,
          presentationName: record.name,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _previewPresentation(PresentationGroupRecord record) async {
    PresentationLoadedGroup? loaded;
    try {
      loaded =
          await PresentationPrepRepository.instance.loadPresentation(record.id);
    } catch (_) {
      if (!mounted) return;
      _showError('Could not load "${record.name}".');
      return;
    }
    if (loaded == null) {
      if (!mounted) return;
      _showError('"${record.name}" was not found.');
      return;
    }
    if (!mounted) return;

    final workspace = buildWorkspaceFromSaved(loaded);
    if (workspace.slides.isEmpty) {
      _showError('"${record.name}" has no slides to preview.');
      return;
    }

    await showTagPresentationSlidePreview(context, workspace: workspace);
  }

  Future<void> _editPresentation(PresentationGroupRecord record) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TagPresentationPrepScreen(
          request: const TagPresentationPrepRequest(tagName: ''),
          editPresentation: record,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _renamePresentation(PresentationGroupRecord record) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(initialName: record.name),
    );

    if (newName == null || newName.isEmpty) return;
    if (newName == record.name) return;

    try {
      await PresentationPrepRepository.instance.renamePresentation(
        record.id,
        newName,
      );
    } on ArgumentError catch (e) {
      if (!mounted) return;
      _showError(e.message.toString());
      return;
    } on StateError catch (e) {
      if (!mounted) return;
      _showError(e.message);
      return;
    } catch (_) {
      if (!mounted) return;
      _showError('Could not rename "${record.name}".');
      return;
    }
    await _load();
  }

  Future<void> _deletePresentation(PresentationGroupRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Presentation'),
        content: Text(
          'Delete "${record.name}"?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await PresentationPrepRepository.instance.deletePresentation(record.id);
    } catch (_) {
      if (!mounted) return;
      _showError('Could not delete "${record.name}".');
      return;
    }
    await _load();
  }

  Future<void> _loadSlidesFor(int presentationId) async {
    if (_loadingSlideIds.contains(presentationId)) return;
    setState(() => _loadingSlideIds.add(presentationId));
    try {
      final slides = await PresentationPrepRepository.instance
          .listSlidesForPresentation(presentationId);
      if (!mounted) return;
      setState(() {
        _slidesByPresId[presentationId] = slides;
        _loadingSlideIds.remove(presentationId);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSlideIds.remove(presentationId));
    }
  }

  Future<void> _toggleExpand(PresentationGroupRecord record) async {
    final id = record.id;
    if (_expandedIds.contains(id)) {
      setState(() => _expandedIds.remove(id));
    } else {
      setState(() => _expandedIds.add(id));
      if (!_slidesByPresId.containsKey(id)) {
        await _loadSlidesFor(id);
      }
    }
  }

  void _copySlideTapped(
    PresentationGroupRecord presentation,
    PresentationSlideRecord slide,
  ) {
    setState(() {
      _copiedSlide = _CopiedSlideInfo(
        sourcePresentationId: presentation.id,
        sourcePresentationName: presentation.name,
        sourceSlideId: slide.id,
        sourceSlideNumber: slide.slideOrder + 1,
      );
    });
  }

  Future<void> _pasteSlideTapped(PresentationGroupRecord target) async {
    final copied = _copiedSlide;
    if (copied == null) return;
    try {
      await PresentationPrepRepository.instance.duplicateSlideToPresentation(
        sourceSlideId: copied.sourceSlideId,
        targetPresentationId: target.id,
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Could not paste slide: ${e.toString()}');
      return;
    }
    if (!mounted) return;
    _slidesByPresId.remove(target.id);
    await _load();
    if (!mounted) return;
    if (_expandedIds.contains(target.id)) {
      await _loadSlidesFor(target.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Slide copied into "${target.name}".')),
    );
  }

  Future<void> _moveSlideUp(
    PresentationGroupRecord presentation,
    int slideId,
  ) async {
    try {
      await PresentationPrepRepository.instance.moveSlideUp(
        presentationId: presentation.id,
        slideId: slideId,
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Could not reorder slide: ${e.toString()}');
      return;
    }
    if (!mounted) return;
    _slidesByPresId.remove(presentation.id);
    await _loadSlidesFor(presentation.id);
  }

  Future<void> _moveSlideDown(
    PresentationGroupRecord presentation,
    int slideId,
  ) async {
    try {
      await PresentationPrepRepository.instance.moveSlideDown(
        presentationId: presentation.id,
        slideId: slideId,
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Could not reorder slide: ${e.toString()}');
      return;
    }
    if (!mounted) return;
    _slidesByPresId.remove(presentation.id);
    await _loadSlidesFor(presentation.id);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Presentations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Error: $_error',
            style: presentationTextStyle(
              context,
              Theme.of(context).textTheme.bodyMedium,
              _fontScale,
              color: Theme.of(context).colorScheme.error,
              minFontSize: 13,
              maxFontSize: 17,
            ),
          ),
        ),
      );
    }

    final banner = _copiedSlide != null
        ? _CopiedSlideBanner(
            info: _copiedSlide!,
            fontScale: _fontScale,
            onClear: () => setState(() => _copiedSlide = null),
          )
        : null;

    if (_presentations.isEmpty) {
      return Column(
        children: [
          if (banner != null) ...[banner],
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.slideshow_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No saved presentations yet.',
                      style: presentationTextStyle(
                        context,
                        Theme.of(context).textTheme.titleMedium,
                        _fontScale,
                        fontWeight: FontWeight.w700,
                        minFontSize: 15,
                        maxFontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use Save Presentation in the prep screen to save your work.',
                      style: presentationTextStyle(
                        context,
                        Theme.of(context).textTheme.bodyMedium,
                        _fontScale,
                        color: Theme.of(context).colorScheme.outline,
                        minFontSize: 13,
                        maxFontSize: 17,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (banner != null) ...[banner],
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _presentations.length,
            separatorBuilder: (context, i) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final record = _presentations[index];
              final isExpanded = _expandedIds.contains(record.id);
              return _PresentationCard(
                record: record,
                copiedSlide: _copiedSlide,
                fontScale: _fontScale,
                isExpanded: isExpanded,
                slides: _slidesByPresId[record.id],
                isLoadingSlides: _loadingSlideIds.contains(record.id),
                onPlay: () => _playPresentation(record),
                onPreview: () => _previewPresentation(record),
                onEdit: () => _editPresentation(record),
                onRename: () => _renamePresentation(record),
                onDelete: () => _deletePresentation(record),
                onToggleExpand: () => _toggleExpand(record),
                onCopySlide: (slide) => _copySlideTapped(record, slide),
                onPasteSlide: () => _pasteSlideTapped(record),
                onMoveUp: (slide) => _moveSlideUp(record, slide.id),
                onMoveDown: (slide) => _moveSlideDown(record, slide.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Card widget
// ---------------------------------------------------------------------------

class _PresentationCard extends StatelessWidget {
  const _PresentationCard({
    required this.record,
    required this.copiedSlide,
    required this.fontScale,
    required this.isExpanded,
    required this.slides,
    required this.isLoadingSlides,
    required this.onPlay,
    required this.onPreview,
    required this.onEdit,
    required this.onRename,
    required this.onDelete,
    required this.onToggleExpand,
    required this.onCopySlide,
    required this.onPasteSlide,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final PresentationGroupRecord record;
  final _CopiedSlideInfo? copiedSlide;
  final double fontScale;
  final bool isExpanded;
  final List<PresentationSlideRecord>? slides;
  final bool isLoadingSlides;
  final VoidCallback onPlay;
  final VoidCallback onPreview;
  final VoidCallback onEdit;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onToggleExpand;
  final void Function(PresentationSlideRecord) onCopySlide;
  final VoidCallback onPasteSlide;
  final void Function(PresentationSlideRecord) onMoveUp;
  final void Function(PresentationSlideRecord) onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceTag = record.sourceTagName?.trim();
    final displayTarget = record.defaultDisplayTarget?.trim();
    final slideCount = record.slideCount;
    final modifiedLabel = _formatDate(record.updatedAt);
    final showPaste = copiedSlide != null;
    final titleStyle = presentationTextStyle(
      context,
      theme.textTheme.titleMedium,
      fontScale,
      fontWeight: FontWeight.w700,
      minFontSize: 15,
      maxFontSize: 22,
    );
    final sourceStyle = presentationTextStyle(
      context,
      theme.textTheme.bodyMedium,
      fontScale,
      color: theme.colorScheme.primary,
      minFontSize: 13,
      maxFontSize: 17,
    );
    final buttonTextStyle = presentationTextStyle(
      context,
      theme.textTheme.labelLarge,
      fontScale,
      fontWeight: FontWeight.w700,
      minFontSize: 12,
      maxFontSize: 17,
    );
    final iconSize = presentationScaledSize(
      context,
      18,
      fontScale,
      min: 18,
      max: 22,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.name,
                        style: titleStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (sourceTag != null && sourceTag.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '#$sourceTag',
                          style: sourceStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _MetaChip(
                            fontScale: fontScale,
                            icon: Icons.view_carousel_outlined,
                            label:
                                '$slideCount ${slideCount == 1 ? 'slide' : 'slides'}',
                          ),
                          _MetaChip(
                            fontScale: fontScale,
                            icon: Icons.schedule_outlined,
                            label: modifiedLabel,
                          ),
                          if (displayTarget != null && displayTarget.isNotEmpty)
                            _MetaChip(
                              fontScale: fontScale,
                              icon: Icons.aspect_ratio_outlined,
                              label: displayTarget,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: slideCount > 0 ? onPlay : null,
                      icon: Icon(Icons.play_arrow, size: iconSize),
                      label: const Text('Play'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        textStyle: buttonTextStyle,
                      ),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: slideCount > 0 ? onPreview : null,
                      icon: Icon(Icons.play_circle_outline, size: iconSize),
                      label: const Text('Preview'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        textStyle: buttonTextStyle,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: onEdit,
                          icon: Icon(Icons.edit_outlined, size: iconSize),
                          tooltip: 'Edit Presentation',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: onToggleExpand,
                          icon: Icon(
                            isExpanded
                                ? Icons.expand_less
                                : Icons.view_list_outlined,
                            size: iconSize,
                          ),
                          tooltip: isExpanded ? 'Hide Slides' : 'Show Slides',
                          visualDensity: VisualDensity.compact,
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, size: iconSize),
                          tooltip: 'More options',
                          padding: EdgeInsets.zero,
                          onSelected: (value) {
                            if (value == 'rename') onRename();
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem<String>(
                              value: 'rename',
                              child: Row(
                                children: [
                                  Icon(Icons.drive_file_rename_outline,
                                      size: 20),
                                  SizedBox(width: 12),
                                  Text('Rename'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: onDelete,
                          icon: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                            size: iconSize,
                          ),
                          tooltip: 'Delete',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    if (showPaste) ...[
                      const SizedBox(height: 6),
                      FilledButton.icon(
                        onPressed: onPasteSlide,
                        icon: Icon(Icons.content_paste, size: iconSize * 0.9),
                        label: const Text('Paste Slide Here'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          textStyle: buttonTextStyle,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
          _SlideListSection(
            slides: slides,
            isLoading: isLoadingSlides,
            fontScale: fontScale,
            onCopySlide: onCopySlide,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}

// ---------------------------------------------------------------------------
// Slide list section (expanded view inside a card)
// ---------------------------------------------------------------------------

class _SlideListSection extends StatelessWidget {
  const _SlideListSection({
    required this.slides,
    required this.isLoading,
    required this.fontScale,
    required this.onCopySlide,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final List<PresentationSlideRecord>? slides;
  final bool isLoading;
  final double fontScale;
  final void Function(PresentationSlideRecord) onCopySlide;
  final void Function(PresentationSlideRecord) onMoveUp;
  final void Function(PresentationSlideRecord) onMoveDown;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final slideList = slides;
    if (slideList == null || slideList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No slides.',
          style: presentationTextStyle(
            context,
            Theme.of(context).textTheme.bodyMedium,
            fontScale,
            color: Theme.of(context).colorScheme.outline,
            minFontSize: 13,
            maxFontSize: 17,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < slideList.length; i++)
          _SlideRow(
            slide: slideList[i],
            number: i + 1,
            fontScale: fontScale,
            onCopySlide: () => onCopySlide(slideList[i]),
            onMoveUp: i > 0 ? () => onMoveUp(slideList[i]) : null,
            onMoveDown:
                i < slideList.length - 1 ? () => onMoveDown(slideList[i]) : null,
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _SlideRow extends StatelessWidget {
  const _SlideRow({
    required this.slide,
    required this.number,
    required this.fontScale,
    required this.onCopySlide,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final PresentationSlideRecord slide;
  final int number;
  final double fontScale;
  final VoidCallback onCopySlide;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = slide.title.trim();
    final displayTitle = title.isNotEmpty ? title : 'Slide $number';
    final header = slide.topHeaderText?.trim() ?? '';
    final footer = slide.bottomFooterText?.trim() ?? '';
    final subtitle = [
      if (header.isNotEmpty) header,
      if (footer.isNotEmpty) footer,
    ].join(' · ');
    final indexStyle = presentationTextStyle(
      context,
      theme.textTheme.labelLarge,
      fontScale,
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      minFontSize: 11,
      maxFontSize: 14,
    );
    final titleStyle = presentationTextStyle(
      context,
      theme.textTheme.bodyMedium,
      fontScale,
      fontWeight: FontWeight.w500,
      minFontSize: 13,
      maxFontSize: 17,
    );
    final subtitleStyle = presentationTextStyle(
      context,
      theme.textTheme.bodySmall,
      fontScale,
      color: theme.colorScheme.outline,
      minFontSize: 11,
      maxFontSize: 14,
    );
    final iconSize = presentationScaledSize(
      context,
      18,
      fontScale,
      min: 18,
      max: 22,
    );
    final buttonTextStyle = presentationTextStyle(
      context,
      theme.textTheme.labelLarge,
      fontScale,
      fontWeight: FontWeight.w700,
      minFontSize: 12,
      maxFontSize: 16,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            radius: 14,
            child: Text('$number', style: indexStyle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle,
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: subtitleStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onMoveUp,
            icon: Icon(Icons.arrow_upward, size: iconSize),
            tooltip: 'Move Up',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onMoveDown,
            icon: Icon(Icons.arrow_downward, size: iconSize),
            tooltip: 'Move Down',
            visualDensity: VisualDensity.compact,
          ),
          OutlinedButton.icon(
            onPressed: onCopySlide,
            icon: Icon(Icons.copy, size: iconSize * 0.8),
            label: const Text('Copy Slide'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              textStyle: buttonTextStyle,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Copied-slide banner
// ---------------------------------------------------------------------------

class _CopiedSlideBanner extends StatelessWidget {
  const _CopiedSlideBanner({
    required this.info,
    required this.fontScale,
    required this.onClear,
  });

  final _CopiedSlideInfo info;
  final double fontScale;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              Icons.copy_outlined,
              size: presentationScaledSize(context, 18, fontScale, min: 18, max: 22),
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Copied slide ${info.sourceSlideNumber} from '
                '"${info.sourcePresentationName}". '
                'Choose a destination and tap Paste Slide Here.',
                style: presentationTextStyle(
                  context,
                  theme.textTheme.bodyMedium,
                  fontScale,
                  color: theme.colorScheme.onPrimaryContainer,
                  minFontSize: 13,
                  maxFontSize: 17,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: presentationTextStyle(
                  context,
                  theme.textTheme.labelLarge,
                  fontScale,
                  fontWeight: FontWeight.w700,
                  minFontSize: 12,
                  maxFontSize: 16,
                ),
              ),
              child: const Text('Clear Copy'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.fontScale,
    required this.icon,
    required this.label,
  });

  final double fontScale;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: presentationScaledSize(context, 13, fontScale, min: 12, max: 15),
          color: theme.colorScheme.outline,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: presentationTextStyle(
            context,
            theme.textTheme.labelLarge ?? theme.textTheme.labelSmall,
            fontScale,
            color: theme.colorScheme.outline,
            fontWeight: FontWeight.w600,
            minFontSize: 11,
            maxFontSize: 14,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rename dialog — owns its controller so dispose is tied to widget removal
// ---------------------------------------------------------------------------

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});
  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename Presentation'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Name',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Workspace reconstruction for preview
// ---------------------------------------------------------------------------

TagPresentationPrepWorkspace buildWorkspaceFromSaved(
  PresentationLoadedGroup loaded, {
  List<UnifiedTagChainItem> additionalItems = const [],
  List<UnifiedTagChain> resolvedChains = const [],
}) {
  final allItems = <UnifiedTagChainItem>[];
  final seenIds = <String>{};

  for (final ls in loaded.slides) {
    for (final item in ls.items) {
      final id = item.sourceItemId ?? 'saved:${item.id}';
      if (!seenIds.add(id)) continue;
      allItems.add(_toChainItem(loaded.group.id, item));
    }
  }

  // Add source-tag items not yet placed on any saved slide
  for (final item in additionalItems) {
    if (seenIds.add(item.id)) {
      allItems.add(item);
    }
  }

  final slides = loaded.slides.map(_toSlide).toList(growable: false);

  final preview = TagPresentationPrepPreview(
    requestedTagName: loaded.group.sourceTagName ?? loaded.group.name,
    sourceSummary: 'Saved presentation: ${loaded.group.name}',
    resolvedChains: List.unmodifiable(resolvedChains),
    items: List.unmodifiable(allItems),
    slides: List.unmodifiable(slides),
  );
  return TagPresentationPrepWorkspace.fromPreview(preview);
}

UnifiedTagChainItem _toChainItem(
  int groupId,
  PresentationItemRecord item,
) {
  final id = item.sourceItemId ?? 'saved:${item.id}';
  final itemType = _itemTypeFromString(item.itemType);
  final mediaPath = item.mediaPath;
  final media = mediaPath != null
      ? [
          UnifiedTagMedia(
            id: 'saved-media:${item.id}',
            itemId: id,
            relativePath: mediaPath,
            mediaType: _guessMediaType(mediaPath),
            sortOrder: 0,
            caption: item.mediaCaption,
          ),
        ]
      : const <UnifiedTagMedia>[];

  return UnifiedTagChainItem(
    id: id,
    chainId: 'saved:$groupId',
    storageKind: UnifiedTagStorageKind.unified,
    sourceType: _sourceTypeFromItemType(itemType),
    itemType: itemType,
    sortOrder: item.itemOrder,
    displayTitle: item.titleOverride,
    textSnapshot: item.bodyOverride,
    media: media,
    rawFields: const <String, Object?>{},
  );
}

TagPresentationPrepSlide _toSlide(PresentationLoadedSlide ls) {
  final profile = ls.profile;
  final rows = profile?.rows ?? 2;
  final columns = profile?.columns ?? 2;

  // Group items by zone_key
  final zoneItemIds = <String, List<String>>{};
  for (final item in ls.items) {
    final id = item.sourceItemId ?? 'saved:${item.id}';
    zoneItemIds.putIfAbsent(item.zoneKey, () => []).add(id);
  }

  // Merged regions
  final mergedRegions = <TagPresentationMergedRegion>[];
  for (final zone in ls.zones.where((z) => z.zoneType == 'merged')) {
    final itemIds = zoneItemIds[zone.zoneKey] ?? const [];
    final regionId = zone.zoneKey.startsWith('merge:')
        ? zone.zoneKey.substring(6)
        : zone.zoneKey;
    mergedRegions.add(TagPresentationMergedRegion(
      id: regionId,
      startRow: zone.startRow,
      startColumn: zone.startColumn,
      rowSpan: zone.rowSpan,
      columnSpan: zone.columnSpan,
      itemIds: List.unmodifiable(itemIds),
    ));
  }

  // Cells (all rows × columns, honouring saved cell zone data)
  final cells = <TagPresentationGridCell>[
    for (var row = 0; row < rows; row++)
      for (var col = 0; col < columns; col++)
        TagPresentationGridCell(
          row: row,
          column: col,
          itemIds: List.unmodifiable(
            zoneItemIds['cell:$row:$col'] ?? const [],
          ),
        ),
  ];

  final gridLayout = TagPresentationGridLayout(
    rows: rows,
    columns: columns,
    cells: cells,
    mergedRegions: mergedRegions,
  );

  return TagPresentationPrepSlide(
    slideNumber: ls.slide.slideOrder + 1,
    label: ls.slide.title,
    gridLayout: gridLayout,
    isDraft: false,
    aspectRatio: _aspectRatioFromProfile(profile),
    topHeaderText: ls.slide.topHeaderText,
    bottomFooterText: ls.slide.bottomFooterText,
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

TagPresentationAspectRatio _aspectRatioFromProfile(
  PresentationProfileRecord? profile,
) {
  if (profile == null) return const TagPresentationAspectRatio.sixteenByNine();
  return switch (profile.aspectRatioPreset) {
    'sixteenByNine' => const TagPresentationAspectRatio.sixteenByNine(),
    'fourByThree' => const TagPresentationAspectRatio.fourByThree(),
    'sixteenByTen' => const TagPresentationAspectRatio.sixteenByTen(),
    'nineBySixteen' => const TagPresentationAspectRatio.nineBySixteen(),
    _ => TagPresentationAspectRatio.custom(
        profile.aspectRatioValue > 0 ? profile.aspectRatioValue : 16 / 9,
      ),
  };
}

UnifiedTagItemType _itemTypeFromString(String? value) {
  return switch (value) {
    'bibleVerse' => UnifiedTagItemType.bibleVerse,
    'bibleRange' => UnifiedTagItemType.bibleRange,
    'eLibraryRange' => UnifiedTagItemType.eLibraryRange,
    'note' => UnifiedTagItemType.note,
    'image' => UnifiedTagItemType.image,
    'media' => UnifiedTagItemType.media,
    'heading' => UnifiedTagItemType.heading,
    _ => UnifiedTagItemType.unknownLegacy,
  };
}

UnifiedTagSourceType _sourceTypeFromItemType(UnifiedTagItemType itemType) {
  return switch (itemType) {
    UnifiedTagItemType.bibleVerse => UnifiedTagSourceType.bible,
    UnifiedTagItemType.bibleRange => UnifiedTagSourceType.bibleRange,
    UnifiedTagItemType.eLibraryRange => UnifiedTagSourceType.eLibrary,
    UnifiedTagItemType.note => UnifiedTagSourceType.note,
    UnifiedTagItemType.image => UnifiedTagSourceType.image,
    UnifiedTagItemType.media => UnifiedTagSourceType.media,
    UnifiedTagItemType.heading => UnifiedTagSourceType.heading,
    UnifiedTagItemType.unknownLegacy => UnifiedTagSourceType.unknownLegacy,
  };
}

String _guessMediaType(String path) {
  final lower = path.trim().toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'application/octet-stream';
}
