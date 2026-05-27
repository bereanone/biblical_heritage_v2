import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/bootstrap/library_root_service.dart';
import '../../../../core/database/study_bible_database.dart';
import '../../data/tags/unified_tag_models.dart';
import '../../data/tags/unified_tag_read_adapter.dart';
import 'tag_presentation_prep_empty_state.dart';
import 'tag_presentation_prep_models.dart';
import 'tag_presentation_prep_state.dart';
import 'tag_card_picker_sheet.dart';
import 'tag_presentation_title_dialog.dart';
import 'tag_presentation_slide_preview.dart';
import 'tag_slide_navigator_panel.dart';
import 'tag_slide_grid_models.dart';
import 'tag_unassigned_card_tray.dart';
import 'tag_working_slide_canvas.dart';
import '../tag_quick_apply_helper.dart';

const bool kPresentationPrepDiagnostics = false;

class TagPresentationPrepScreen extends StatefulWidget {
  const TagPresentationPrepScreen({
    super.key,
    required this.request,
    required this.adapter,
  });

  final TagPresentationPrepRequest request;
  final UnifiedTagReadAdapter adapter;

  @override
  State<TagPresentationPrepScreen> createState() =>
      _TagPresentationPrepScreenState();
}

class _TagPresentationPrepScreenState extends State<TagPresentationPrepScreen> {
  bool _loading = true;
  String? _error;
  TagPresentationPrepPreview? _preview;
  TagPresentationPrepWorkspace? _workspace;
  String? _mediaRootPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final preview = await _resolvePreview();
      final mediaRootPath = await LibraryRootService.instance
          .accessibleLibraryRootPath();
      if (!mounted) return;
      final workspace = TagPresentationPrepWorkspace.fromPreview(preview);
      assert(() {
        if (kPresentationPrepDiagnostics) {
          _logPrepDiagnostics(preview: preview, workspace: workspace);
        }
        return true;
      }());
      setState(() {
        _preview = preview;
        _workspace = workspace;
        _mediaRootPath = mediaRootPath;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<TagPresentationPrepPreview> _resolvePreview() async {
    final requestedTag = (widget.request.tagName ?? '').trim();
    if ((widget.request.chainId ?? '').trim().isNotEmpty) {
      final chain = await widget.adapter.loadChainById(widget.request.chainId!);
      if (chain != null) {
        final items =
            chain.items.where((item) => !item.isDeleted).toList(growable: false)
              ..sort(_comparePreviewItems);
        return _buildPreview(
          requestedTagName: requestedTag.isEmpty ? chain.name : requestedTag,
          activeChain: chain,
          resolvedChains: [chain],
          items: items,
          sourceSummary:
              'Selected ${_storageLabel(chain.storageKind)} chain by id.',
        );
      }
    }

    final preferredKinds = widget.request.preferredStorageKinds.toSet();
    if (requestedTag.isNotEmpty &&
        preferredKinds.contains(UnifiedTagStorageKind.hash)) {
      final legacyPreview = await _resolveLegacyHashPreview(
        requestedTagName: requestedTag,
      );
      if (legacyPreview != null) {
        return legacyPreview;
      }
    }

    if (requestedTag.isEmpty) {
      return const TagPresentationPrepPreview(
        requestedTagName: '',
        sourceSummary: 'No #tag selected.',
        resolvedChains: <UnifiedTagChain>[],
        items: <UnifiedTagChainItem>[],
        slides: <TagPresentationPrepSlide>[],
      );
    }

    final snapshot = await widget.adapter.loadSnapshot();
    final matchingChains =
        snapshot.chains
            .where((chain) {
              final matchesTag =
                  _tagMatches(chain.name, requestedTag) ||
                  _tagMatches(chain.legacyTagName, requestedTag);
              if (!matchesTag) return false;
              if (chain.storageKind == UnifiedTagStorageKind.dollar) {
                return false;
              }
              return preferredKinds.contains(chain.storageKind) ||
                  chain.storageKind == UnifiedTagStorageKind.unified ||
                  chain.storageKind == UnifiedTagStorageKind.hash;
            })
            .toList(growable: false)
          ..sort(_compareChainPriority);

    if (matchingChains.isEmpty) {
      return TagPresentationPrepPreview(
        requestedTagName: requestedTag,
        sourceSummary: 'No matching #tag chain was found.',
        resolvedChains: const <UnifiedTagChain>[],
        items: const <UnifiedTagChainItem>[],
        slides: const <TagPresentationPrepSlide>[],
      );
    }

    final activeChain = matchingChains.first;
    final items =
        activeChain.items
            .where((item) => !item.isDeleted)
            .toList(growable: false)
          ..sort(_comparePreviewItems);

    return _buildPreview(
      requestedTagName: requestedTag,
      activeChain: activeChain,
      resolvedChains: [activeChain],
      items: items,
      sourceSummary: _sourceSummaryForSelection(
        activeChain: activeChain,
        matchingChains: matchingChains,
      ),
    );
  }

  Future<TagPresentationPrepPreview?> _resolveLegacyHashPreview({
    required String requestedTagName,
  }) async {
    final repository = HashTagRepository();
    final entries = await repository.loadEntries(
      requestedTagName,
      sortMode: HashTagEntrySortMode.slideOrder,
    );
    if (entries.isEmpty) return null;

    final bookNames = await _loadBookNames();
    final items = <UnifiedTagChainItem>[
      for (final entry in entries)
        _legacyHashEntryToPresentationItem(
          entry: entry,
          bookNames: bookNames,
          tagName: requestedTagName,
        ),
    ];
    final chain = UnifiedTagChain(
      id: 'legacy:hash:${Uri.encodeComponent(_normalizeTag(requestedTagName))}',
      name: _normalizeTag(requestedTagName),
      storageKind: UnifiedTagStorageKind.hash,
      isDefault: false,
      legacyTable: 'hash_tags',
      legacyTagName: _normalizeTag(requestedTagName),
      createdAt: null,
      updatedAt: null,
      rawFields: const <String, Object?>{},
      items: List.unmodifiable(items),
    );
    return _buildPreview(
      requestedTagName: requestedTagName,
      activeChain: chain,
      resolvedChains: [chain],
      items: items,
      sourceSummary: 'Selected legacy hash chain by repository lookup.',
    );
  }

  Future<Map<int, String>> _loadBookNames() async {
    final books = await StudyBibleDatabase.instance.loadBooks();
    return {for (final book in books) book.bookNumber: book.bookName};
  }

  UnifiedTagChainItem _legacyHashEntryToPresentationItem({
    required HashTagEntry entry,
    required Map<int, String> bookNames,
    required String tagName,
  }) {
    final hasMedia = entry.mediaRefs.isNotEmpty;
    final media = <UnifiedTagMedia>[
      for (final ref in entry.mediaRefs)
        UnifiedTagMedia(
          id: 'legacy-media:${entry.id}:${ref.hashCode}',
          itemId: '${entry.id}',
          relativePath: ref,
          mediaType: _mediaTypeForPath(ref),
          sortOrder: 0,
          caption: null,
        ),
    ];
    final title = _legacyHashEntryTitle(entry, bookNames);
    final body = _legacyHashEntryBody(entry);
    final itemType = hasMedia
        ? (media.every(
                (entry) => entry.mediaType.toLowerCase().startsWith('image/'),
              )
              ? UnifiedTagItemType.image
              : UnifiedTagItemType.media)
        : _legacyHashEntryItemType(entry);

    return UnifiedTagChainItem(
      id: 'legacy:hash:${_normalizeTag(tagName)}:${entry.id}',
      chainId: 'legacy:hash:${Uri.encodeComponent(_normalizeTag(tagName))}',
      storageKind: UnifiedTagStorageKind.hash,
      sourceType: switch (itemType) {
        UnifiedTagItemType.bibleVerse => UnifiedTagSourceType.bible,
        UnifiedTagItemType.bibleRange => UnifiedTagSourceType.bibleRange,
        UnifiedTagItemType.eLibraryRange => UnifiedTagSourceType.eLibrary,
        UnifiedTagItemType.note => UnifiedTagSourceType.note,
        UnifiedTagItemType.image => UnifiedTagSourceType.image,
        UnifiedTagItemType.media => UnifiedTagSourceType.media,
        UnifiedTagItemType.heading => UnifiedTagSourceType.heading,
        UnifiedTagItemType.unknownLegacy => UnifiedTagSourceType.unknownLegacy,
      },
      itemType: itemType,
      sortOrder: entry.sortOrder,
      displayTitle: title,
      textSnapshot: body,
      noteText: entry.noteText,
      htmlContent: entry.contentHtml,
      media: List.unmodifiable(media),
      bibleAnchor: entry.verseRef.trim().isNotEmpty
          ? UnifiedTagBibleAnchor(
              bookNumber: entry.bookNumber,
              chapter: entry.chapter,
              verseStart: entry.verse,
              verseEnd: entry.verseEnd,
              verseRef: entry.verseRef,
            )
          : null,
      elibraryAnchor: null,
      layoutHint: null,
      legacyTable: 'hash_tags',
      legacyTagName: _normalizeTag(tagName),
      legacyItemId: '${entry.id}',
      legacyGroupId: null,
      legacyImportPackageId: null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        entry.createdAt,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        entry.createdAt,
        isUtc: true,
      ),
      deletedAt: null,
      rawFields: <String, Object?>{
        'legacy_hash_entry_id': entry.id,
        'presentation_media_count': entry.mediaRefs.length,
      },
    );
  }

  UnifiedTagItemType _legacyHashEntryItemType(HashTagEntry entry) {
    final noteText = entry.noteText?.trim() ?? '';
    final bodyText = entry.contentHtml?.trim() ?? '';
    if ((noteText.isNotEmpty || bodyText.isNotEmpty) && entry.verse == 0) {
      return UnifiedTagItemType.note;
    }
    return entry.verseEnd > entry.verse
        ? UnifiedTagItemType.bibleRange
        : UnifiedTagItemType.bibleVerse;
  }

  String _legacyHashEntryTitle(HashTagEntry entry, Map<int, String> bookNames) {
    final userTitle = entry.userTitle?.trim() ?? '';
    if (userTitle.isNotEmpty) return userTitle;
    final displayOverride = entry.displayTextOverride?.trim() ?? '';
    if (displayOverride.isNotEmpty) return displayOverride;
    final referenceCode = entry.referenceCode?.trim() ?? '';
    if (referenceCode.isNotEmpty) return referenceCode;
    final bookName = bookNames[entry.bookNumber]?.trim() ?? '';
    final resolvedBook = bookName.isNotEmpty
        ? bookName
        : 'Book ${entry.bookNumber}';
    final verseLabel = entry.verseEnd > entry.verse
        ? '${entry.verse}-${entry.verseEnd}'
        : '${entry.verse}';
    return '$resolvedBook ${entry.chapter}:$verseLabel';
  }

  String? _legacyHashEntryBody(HashTagEntry entry) {
    final displayOverride = entry.displayTextOverride?.trim() ?? '';
    if (displayOverride.isNotEmpty) return displayOverride;
    final verseText = entry.verseText.trim();
    if (verseText.isNotEmpty) return verseText;
    final noteText = entry.noteText?.trim() ?? '';
    if (noteText.isNotEmpty) return noteText;
    return entry.contentHtml?.trim().isNotEmpty == true
        ? _cleanText(entry.contentHtml!)
        : null;
  }

  String _mediaTypeForPath(String path) {
    final lower = path.trim().toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return 'image/${lower.endsWith('.jpg') || lower.endsWith('.jpeg') ? 'jpeg' : lower.split('.').last}';
    }
    return 'application/octet-stream';
  }

  TagPresentationPrepPreview _buildPreview({
    required String requestedTagName,
    required UnifiedTagChain activeChain,
    required List<UnifiedTagChain> resolvedChains,
    required List<UnifiedTagChainItem> items,
    required String sourceSummary,
  }) {
    final presentationItems = _expandPresentationItems(items);
    return TagPresentationPrepPreview(
      requestedTagName: requestedTagName.isNotEmpty
          ? requestedTagName
          : activeChain.name,
      sourceSummary: sourceSummary,
      resolvedChains: List.unmodifiable(resolvedChains),
      items: List.unmodifiable(presentationItems),
      slides: List.unmodifiable(
        buildTagPresentationPrepSlides(presentationItems),
      ),
    );
  }

  void _updateWorkspace(
    void Function(TagPresentationPrepWorkspace workspace) action,
  ) {
    final workspace = _workspace;
    if (workspace == null) return;
    setState(() {
      action(workspace);
    });
  }

  void _handleItemSelected(String itemId) {
    _updateWorkspace((workspace) {
      workspace.selectItem(itemId);
    });
  }

  void _handleCellSelected(TagPresentationGridCellCoordinate cell) {
    _updateWorkspace((workspace) {
      if (workspace.mergeSelectionMode) {
        workspace.toggleMergeSelectionCell(cell.row, cell.column);
      } else {
        workspace.selectCell(cell.row, cell.column);
      }
    });
  }

  void _handleNewBlankSlide() {
    _updateWorkspace((workspace) {
      workspace.newBlankSlide();
    });
    _showSnack('Created a new blank slide.');
  }

  void _handleCardDropped(
    String itemId,
    Offset normalizedCenter,
    double normalizedWidth,
    double normalizedHeight,
    bool avoidOverlap,
  ) {
    final workspace = _workspace;
    if (workspace == null) return;
    final changed = workspace.placeItemOnSelectedSlide(
      itemId,
      normalizedCenter,
      normalizedWidth: normalizedWidth,
      normalizedHeight: normalizedHeight,
      avoidOverlap: avoidOverlap,
    );
    if (!changed) return;
    setState(() {});
  }

  void _handleCardRemoved(String itemId) {
    final workspace = _workspace;
    if (workspace == null) return;
    final changed = workspace.removeItemFromSelectedSlide(itemId);
    if (!changed) return;
    setState(() {});
  }

  Future<void> _chooseCardForSelectedZone() async {
    final workspace = _workspace;
    if (workspace == null) return;
    if (!workspace.hasSelectedZone) {
      _showSnack('Tap a cell or merged zone first.');
      return;
    }
    final selectedItem = await showTagCardPickerSheet(
      context,
      items: workspace.unassignedItems,
      zoneLabel: workspace.selectedZoneLabel,
    );
    if (selectedItem == null) return;
    final changed = workspace.assignItemToSelectedZone(selectedItem.id);
    if (!changed) {
      await _showErrorDialog('Could not add the card to the selected zone.');
      return;
    }
    setState(() {});
  }

  Future<void> _addTitle() async {
    final workspace = _workspace;
    if (workspace == null) return;
    final draft = await showTagPresentationTitleDialog(
      context,
      topHeaderText: workspace.selectedSlide?.topHeaderText,
      bottomFooterText: workspace.selectedSlide?.bottomFooterText,
    );
    if (draft == null) return;
    final updatedTop = workspace.setTopTitleForSelectedSlide(
      draft.topHeaderText,
    );
    final updatedBottom = workspace.setBottomTitleForSelectedSlide(
      draft.bottomFooterText,
    );
    if (!updatedTop || !updatedBottom) {
      await _showErrorDialog(
        'Could not update the header/footer fields.',
        title: 'Could not update header/footer',
      );
      return;
    }
    setState(() {});
  }

  Future<void> _editCustomAspectRatio() async {
    final workspace = _workspace;
    if (workspace == null) return;
    final current = workspace.selectedAspectRatioSetting;
    final custom = await showDialog<TagPresentationAspectRatio>(
      context: context,
      builder: (context) {
        return _CustomAspectRatioDialog(initialAspectRatio: current);
      },
    );
    if (custom == null) return;
    _updateWorkspace((workspace) {
      workspace.setSelectedAspectRatio(custom);
    });
  }

  Future<void> _previewSelectedSlide() async {
    final workspace = _workspace;
    if (workspace == null) return;
    if (workspace.selectedSlide == null) {
      _showSnack('No slide selected.');
      return;
    }
    await showTagPresentationSlidePreview(context, workspace: workspace);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showErrorDialog(
    String message, {
    String title = 'Could not place card',
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  bool _tagMatches(String? candidate, String requested) {
    final left = _normalizeTag(candidate ?? '');
    final right = _normalizeTag(requested);
    return left.isNotEmpty && left == right;
  }

  String _normalizeTag(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceFirst(RegExp(r'^[#\$@]+'), '');
  }

  int _compareChainPriority(UnifiedTagChain left, UnifiedTagChain right) {
    final richnessCompare = _chainRichnessScore(
      right,
    ).compareTo(_chainRichnessScore(left));
    if (richnessCompare != 0) return richnessCompare;

    final priorityCompare = _storagePriority(
      left.storageKind,
    ).compareTo(_storagePriority(right.storageKind));
    if (priorityCompare != 0) return priorityCompare;
    final nameCompare = left.name.toLowerCase().compareTo(
      right.name.toLowerCase(),
    );
    if (nameCompare != 0) return nameCompare;
    return left.id.compareTo(right.id);
  }

  int _chainRichnessScore(UnifiedTagChain chain) {
    final itemCount = chain.items.length;
    final mediaCount = chain.items.fold<int>(
      0,
      (sum, item) => sum + item.media.length,
    );
    final storageBonus = switch (chain.storageKind) {
      UnifiedTagStorageKind.hash => 3,
      UnifiedTagStorageKind.unified => 2,
      UnifiedTagStorageKind.dollar => 1,
      UnifiedTagStorageKind.unknownLegacy => 0,
    };
    return itemCount * 1000 + mediaCount * 10 + storageBonus;
  }

  int _storagePriority(UnifiedTagStorageKind storageKind) {
    return switch (storageKind) {
      UnifiedTagStorageKind.hash => 0,
      UnifiedTagStorageKind.unified => 1,
      UnifiedTagStorageKind.dollar => 2,
      UnifiedTagStorageKind.unknownLegacy => 3,
    };
  }

  String _storageLabel(UnifiedTagStorageKind storageKind) {
    return switch (storageKind) {
      UnifiedTagStorageKind.unified => 'unified',
      UnifiedTagStorageKind.hash => 'legacy hash',
      UnifiedTagStorageKind.dollar => 'legacy dollar',
      UnifiedTagStorageKind.unknownLegacy => 'legacy',
    };
  }

  String? _cleanText(String? value) {
    final cleaned = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return cleaned.isEmpty ? null : cleaned;
  }

  int _comparePreviewItems(
    UnifiedTagChainItem left,
    UnifiedTagChainItem right,
  ) {
    final sortCompare = left.sortOrder.compareTo(right.sortOrder);
    if (sortCompare != 0) return sortCompare;
    final leftCreated =
        left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final rightCreated =
        right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final createdCompare = leftCreated.compareTo(rightCreated);
    if (createdCompare != 0) return createdCompare;
    return left.id.compareTo(right.id);
  }

  String _sourceSummaryForSelection({
    required UnifiedTagChain activeChain,
    required List<UnifiedTagChain> matchingChains,
  }) {
    if (matchingChains.length <= 1) {
      return 'Selected ${_storageLabel(activeChain.storageKind)} chain.';
    }

    final ignoredCount = matchingChains.length - 1;
    return 'Selected ${_storageLabel(activeChain.storageKind)} chain. '
        '$ignoredCount additional matching chain${ignoredCount == 1 ? '' : 's'} were ignored.';
  }

  List<UnifiedTagChainItem> _expandPresentationItems(
    List<UnifiedTagChainItem> rawItems,
  ) {
    final expanded = <UnifiedTagChainItem>[];
    for (final item in rawItems) {
      expanded.add(item);

      if (item.media.isEmpty) continue;
      if (item.itemType == UnifiedTagItemType.image ||
          item.itemType == UnifiedTagItemType.media) {
        continue;
      }

      for (var index = 0; index < item.media.length; index++) {
        final media = item.media[index];
        final isImage = media.mediaType.toLowerCase().startsWith('image/');
        expanded.add(
          UnifiedTagChainItem(
            id: '${item.id}::media:${media.id}',
            chainId: item.chainId,
            storageKind: item.storageKind,
            sourceType: isImage
                ? UnifiedTagSourceType.image
                : UnifiedTagSourceType.media,
            itemType: isImage
                ? UnifiedTagItemType.image
                : UnifiedTagItemType.media,
            sortOrder: item.sortOrder * 1000 + index + 1,
            displayTitle: _mediaDisplayTitle(item, media),
            textSnapshot:
                _cleanText(item.noteText) ??
                _cleanText(item.textSnapshot) ??
                _cleanText(item.htmlContent),
            noteText: item.noteText,
            htmlContent: item.htmlContent,
            media: [media],
            bibleAnchor: item.bibleAnchor,
            elibraryAnchor: item.elibraryAnchor,
            layoutHint: item.layoutHint,
            legacyTable: item.legacyTable,
            legacyTagName: item.legacyTagName,
            legacyTagId: item.legacyTagId,
            legacyItemId: item.legacyItemId,
            legacyGroupId: item.legacyGroupId,
            legacyImportPackageId: item.legacyImportPackageId,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            deletedAt: item.deletedAt,
            rawFields: {
              ...item.rawFields,
              'presentation_media_id': media.id,
              'presentation_media_relative_path': media.relativePath,
              if (media.caption != null)
                'presentation_media_caption': media.caption,
            },
          ),
        );
      }
    }
    return expanded;
  }

  String _mediaDisplayTitle(UnifiedTagChainItem item, UnifiedTagMedia media) {
    final isImage = media.mediaType.toLowerCase().startsWith('image/');
    final typeLabel = isImage ? 'Image' : 'Media';
    final caption = _cleanText(media.caption);
    if (caption != null) return '$typeLabel: $caption';
    final path = _cleanText(media.relativePath);
    if (path != null) {
      final filename = path.split('/').last;
      return '$typeLabel: $filename';
    }
    final parentTitle = _cleanText(item.displayTitle);
    if (parentTitle != null) return '$typeLabel: $parentTitle';
    return typeLabel;
  }

  void _logPrepDiagnostics({
    required TagPresentationPrepPreview preview,
    required TagPresentationPrepWorkspace workspace,
  }) {
    if (!kPresentationPrepDiagnostics) return;

    debugPrint(
      'Prep diag: chains=${preview.resolvedChains.length} '
      'items=${workspace.items.length} available=${workspace.unassignedItems.length}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final workspace = _workspace;
    final requestedTag =
        preview?.requestedTagName ?? widget.request.displayTitle;

    return Scaffold(
      appBar: AppBar(title: const Text('Presentation Preparation')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
            final viewportHeight = viewportConstraints.maxHeight;
            return _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: TagPresentationPrepEmptyState(
                      title: 'Presentation Preparation',
                      message: 'Unable to load the selected #tag chain.',
                      hint: _error,
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: viewportHeight),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1600),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _HeaderCard(tagName: requestedTag),
                              const SizedBox(height: 12),
                              if (workspace == null)
                                const TagPresentationPrepEmptyState(
                                  title: 'No workspace loaded',
                                  message:
                                      'Open this screen from a #tag detail view.',
                                  hint:
                                      'The selected #tag name is passed into this screen.',
                                )
                              else
                                _PresentationPrepWorkspaceLayout(
                                  workspace: workspace,
                                  mediaRootPath: _mediaRootPath,
                                  viewportHeight: viewportHeight,
                                  onWorkspaceChanged: () => setState(() {}),
                                  onCardSelected: _handleItemSelected,
                                  onCardDropped: _handleCardDropped,
                                  onRemoveCard: _handleCardRemoved,
                                  onCellSelected: _handleCellSelected,
                                  onNewBlankSlide: _handleNewBlankSlide,
                                  onPreviewSlide: _previewSelectedSlide,
                                  onChooseCardPressed:
                                      _chooseCardForSelectedZone,
                                  onAddTitlePressed: _addTitle,
                                  onAspectRatioPresetChanged: (preset) {
                                    if (preset == null) return;
                                    _updateWorkspace((workspace) {
                                      final slide = workspace.selectedSlide;
                                      if (slide == null) return;
                                      final current = slide.aspectRatio;
                                      workspace.setSelectedAspectRatio(switch (preset) {
                                        TagPresentationAspectRatioPreset
                                            .sixteenByNine =>
                                          const TagPresentationAspectRatio.sixteenByNine(),
                                        TagPresentationAspectRatioPreset
                                            .fourByThree =>
                                          const TagPresentationAspectRatio.fourByThree(),
                                        TagPresentationAspectRatioPreset
                                            .sixteenByTen =>
                                          const TagPresentationAspectRatio.sixteenByTen(),
                                        TagPresentationAspectRatioPreset
                                            .nineBySixteen =>
                                          const TagPresentationAspectRatio.nineBySixteen(),
                                        TagPresentationAspectRatioPreset
                                            .custom =>
                                          current.copyWith(
                                            preset:
                                                TagPresentationAspectRatioPreset
                                                    .custom,
                                          ),
                                      });
                                    });
                                  },
                                  onEditCustomAspectRatio:
                                      _editCustomAspectRatio,
                                  onRowsChanged: (rows) {
                                    _updateWorkspace((workspace) {
                                      workspace.setSelectedGridRows(rows);
                                    });
                                  },
                                  onColumnsChanged: (columns) {
                                    _updateWorkspace((workspace) {
                                      workspace.setSelectedGridColumns(columns);
                                    });
                                  },
                                  onMergeCellsPressed: () {
                                    _updateWorkspace((workspace) {
                                      if (workspace.mergeSelectionMode) {
                                        if (workspace.canApplySelectedMerge) {
                                          workspace.applySelectedMerge();
                                        }
                                      } else {
                                        workspace.startMergeSelection();
                                      }
                                    });
                                  },
                                  onUnmergePressed: () {
                                    _updateWorkspace((workspace) {
                                      workspace.unmergeSelectedRegion();
                                    });
                                  },
                                  onCancelMergePressed: () {
                                    _updateWorkspace((workspace) {
                                      workspace.cancelMergeSelection();
                                    });
                                  },
                                  canApplyMerge: !workspace.mergeSelectionMode
                                      ? true
                                      : workspace.canApplySelectedMerge,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
          },
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.tagName});

  final String tagName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Presentation Preparation',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text('Preparing: $tagName', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Use Choose Card to place cards, edit the slide frame above, and preview when ready.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _PresentationPrepWorkspaceLayout extends StatelessWidget {
  const _PresentationPrepWorkspaceLayout({
    required this.workspace,
    required this.mediaRootPath,
    required this.viewportHeight,
    required this.onWorkspaceChanged,
    required this.onCardSelected,
    required this.onCardDropped,
    required this.onRemoveCard,
    required this.onCellSelected,
    required this.onNewBlankSlide,
    required this.onPreviewSlide,
    required this.onChooseCardPressed,
    required this.onAddTitlePressed,
    required this.onAspectRatioPresetChanged,
    required this.onEditCustomAspectRatio,
    required this.onRowsChanged,
    required this.onColumnsChanged,
    required this.onMergeCellsPressed,
    required this.onUnmergePressed,
    required this.onCancelMergePressed,
    required this.canApplyMerge,
  });

  final TagPresentationPrepWorkspace workspace;
  final String? mediaRootPath;
  final double viewportHeight;
  final VoidCallback onWorkspaceChanged;
  final ValueChanged<String> onCardSelected;
  final void Function(
    String itemId,
    Offset normalizedCenter,
    double normalizedWidth,
    double normalizedHeight,
    bool avoidOverlap,
  )
  onCardDropped;
  final ValueChanged<String> onRemoveCard;
  final ValueChanged<TagPresentationGridCellCoordinate>? onCellSelected;
  final VoidCallback onNewBlankSlide;
  final VoidCallback onPreviewSlide;
  final VoidCallback onChooseCardPressed;
  final VoidCallback onAddTitlePressed;
  final ValueChanged<TagPresentationAspectRatioPreset?>
  onAspectRatioPresetChanged;
  final VoidCallback onEditCustomAspectRatio;
  final ValueChanged<int> onRowsChanged;
  final ValueChanged<int> onColumnsChanged;
  final VoidCallback onMergeCellsPressed;
  final VoidCallback onUnmergePressed;
  final VoidCallback onCancelMergePressed;
  final bool canApplyMerge;

  @override
  Widget build(BuildContext context) {
    final workspace = this.workspace;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final selectedSlide = workspace.selectedSlide;
        final aspectRatio = selectedSlide?.aspectRatio.aspectRatio ?? 16 / 9;
        final compactWidth = availableWidth < 760;
        final controlsWidth = compactWidth
            ? availableWidth
            : math.min(360.0, math.max(320.0, availableWidth * 0.26));
        final gap = compactWidth ? 0.0 : 16.0;
        final slideWidth = compactWidth
            ? availableWidth
            : math.max(0.0, availableWidth - controlsWidth - gap);
        final slideHeight = _estimateSlideWorkspaceHeight(
          slideWidth: slideWidth,
          aspectRatio: aspectRatio,
          viewportHeight: viewportHeight,
        );

        final navigator = TagSlideNavigatorPanel(
          workspace: workspace,
          onNewBlankSlide: onNewBlankSlide,
          onPreviewSlide: onPreviewSlide,
          onChooseCardPressed: onChooseCardPressed,
          onAddTitlePressed: onAddTitlePressed,
          onAspectRatioPresetChanged: onAspectRatioPresetChanged,
          onEditCustomAspectRatio: onEditCustomAspectRatio,
          onRowsChanged: onRowsChanged,
          onColumnsChanged: onColumnsChanged,
          onMergeCellsPressed: onMergeCellsPressed,
          onUnmergePressed: onUnmergePressed,
          onCancelMergePressed: onCancelMergePressed,
          canApplyMerge: canApplyMerge,
        );

        final canvas = SizedBox(
          width: double.infinity,
          height: slideHeight,
          child: TagWorkingSlideCanvas(
            workspace: workspace,
            onCardSelected: onCardSelected,
            onCardDropped: onCardDropped,
            onRemoveCard: onRemoveCard,
            onWorkspaceChanged: onWorkspaceChanged,
            onCellSelected: onCellSelected,
            mediaRootPath: mediaRootPath,
          ),
        );

        final cardsTray = TagUnassignedCardTray(
          availableCount: workspace.unassignedItems.length,
          onBrowseCards: onChooseCardPressed,
        );

        final mainBody = compactWidth
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [canvas, const SizedBox(height: 16), navigator],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: canvas),
                  SizedBox(width: gap),
                  SizedBox(width: controlsWidth, child: navigator),
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [mainBody, const SizedBox(height: 16), cardsTray],
        );
      },
    );
  }

  double _estimateSlideWorkspaceHeight({
    required double slideWidth,
    required double aspectRatio,
    required double viewportHeight,
  }) {
    if (slideWidth <= 0) {
      return viewportHeight < 720 ? 360.0 : 420.0;
    }
    final slideHeight = slideWidth / aspectRatio;
    final chromeHeight = math.max(80.0, viewportHeight * 0.06);
    final idealHeight = slideHeight + chromeHeight;
    final maxEditorHeight = viewportHeight < 720 ? 400.0 : 460.0;
    return math.min(idealHeight, maxEditorHeight);
  }
}

class _CustomAspectRatioDialog extends StatefulWidget {
  const _CustomAspectRatioDialog({required this.initialAspectRatio});

  final TagPresentationAspectRatio initialAspectRatio;

  @override
  State<_CustomAspectRatioDialog> createState() =>
      _CustomAspectRatioDialogState();
}

class _CustomAspectRatioDialogState extends State<_CustomAspectRatioDialog> {
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;

  @override
  void initState() {
    super.initState();
    final ratio = widget.initialAspectRatio.aspectRatio;
    final width = ratio >= 1 ? 16.0 : 9.0;
    final height = ratio >= 1 ? width / ratio : 16.0;
    _widthController = TextEditingController(text: width.toStringAsFixed(0));
    _heightController = TextEditingController(text: height.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = double.tryParse(_widthController.text.trim()) ?? 16.0;
    final height = double.tryParse(_heightController.text.trim()) ?? 9.0;
    final ratio = width > 0 && height > 0 ? width / height : 16 / 9;
    return AlertDialog(
      title: const Text('Custom Aspect Ratio'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _widthController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Width',
                      hintText: '16',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  ':',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      hintText: '9',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Preview: ${ratio.isFinite ? ratio.toStringAsFixed(2) : '16:9'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final width = double.tryParse(_widthController.text.trim()) ?? 16.0;
            final height =
                double.tryParse(_heightController.text.trim()) ?? 9.0;
            Navigator.of(context).pop(
              TagPresentationAspectRatio.custom(
                width > 0 && height > 0 ? width / height : 16 / 9,
              ),
            );
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
