import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/bootstrap/library_root_service.dart';
import '../../../../core/database/study_bible_database.dart';
import '../../../../core/theme/app_settings_service.dart';
import '../../data/presentation/presentation_prep_db_models.dart';
import '../../data/presentation/presentation_prep_repository.dart';
import '../../data/tags/unified_tag_models.dart';
import '../../data/tags/unified_tag_read_adapter.dart';
import 'presentation_ui_helpers.dart';
import 'tag_presentation_prep_empty_state.dart';
import 'tag_presentation_prep_models.dart';
import 'tag_presentation_prep_state.dart';
import 'tag_card_picker_sheet.dart';
import 'tag_presentation_title_dialog.dart';
import 'tag_presentation_slide_preview.dart';
import 'tag_saved_presentations_screen.dart';
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
    this.adapter,
    this.editPresentation,
  });

  final TagPresentationPrepRequest request;
  final UnifiedTagReadAdapter? adapter;
  final PresentationGroupRecord? editPresentation;

  @override
  State<TagPresentationPrepScreen> createState() =>
      _TagPresentationPrepScreenState();
}

class _TagPresentationPrepScreenState extends State<TagPresentationPrepScreen> {
  bool _loading = true;
  String? _error;
  double _fontScale = 1.3;
  TagPresentationPrepPreview? _preview;
  TagPresentationPrepWorkspace? _workspace;
  String? _mediaRootPath;
  PresentationGroupRecord? _editGroupRecord;

  bool get _editMode => widget.editPresentation != null;

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
    try {
      final mediaRootPath = await LibraryRootService.instance
          .accessibleLibraryRootPath();
      if (_editMode) {
        await _loadEditMode(mediaRootPath);
        return;
      }
      final preview = await _resolvePreview();
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

  Future<void> _loadEditMode(String? mediaRootPath) async {
    final rec = widget.editPresentation!;
    PresentationLoadedGroup? loaded;
    try {
      loaded = await PresentationPrepRepository.instance.loadPresentation(
        rec.id,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load "${rec.name}": ${e.toString()}';
      });
      return;
    }
    if (loaded == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Presentation "${rec.name}" was not found.';
      });
      return;
    }
    // Try to reload the full source-tag card list so the picker can offer
    // cards that weren't included in the original saved deck. Best-effort:
    // a failure here must not block the editor from opening.
    List<UnifiedTagChainItem> sourceItems = const [];
    List<UnifiedTagChain> sourceChains = const [];
    String sourceSummary;
    try {
      final reloaded = await _reloadSourceTagItems(loaded.group);
      sourceItems = reloaded.$1;
      sourceChains = reloaded.$2;
      sourceSummary = sourceItems.isNotEmpty
          ? 'Editing "${rec.name}" — source tag loaded.'
          : _hasSourceTag(loaded.group)
          ? 'Editing "${rec.name}" — source tag unavailable.'
          : 'Editing saved presentation.';
    } catch (_) {
      sourceSummary = 'Editing saved presentation.';
    }

    if (!mounted) return;
    final workspace = buildWorkspaceFromSaved(
      loaded,
      additionalItems: sourceItems,
      resolvedChains: sourceChains,
    );
    final preview = TagPresentationPrepPreview(
      requestedTagName: loaded.group.sourceTagName ?? loaded.group.name,
      sourceSummary: sourceSummary,
      resolvedChains: const [],
      items: const [],
      slides: const [],
    );
    setState(() {
      _editGroupRecord = loaded!.group;
      _preview = preview;
      _workspace = workspace;
      _mediaRootPath = mediaRootPath;
      _loading = false;
      _error = null;
    });
  }

  Future<TagPresentationPrepPreview> _resolvePreview() async {
    final requestedTag = (widget.request.tagName ?? '').trim();
    if ((widget.request.chainId ?? '').trim().isNotEmpty) {
      final chain = await widget.adapter!.loadChainById(
        widget.request.chainId!,
      );
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

    final snapshot = await widget.adapter!.loadSnapshot();
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

  bool _hasSourceTag(PresentationGroupRecord group) {
    return (group.sourceTagKey?.isNotEmpty ?? false) ||
        (group.sourceTagId?.isNotEmpty ?? false) ||
        (group.sourceTagName?.isNotEmpty ?? false);
  }

  /// Reloads all items from the original source tag so the card picker can
  /// offer unused cards when editing a saved presentation. Returns empty lists
  /// when no source metadata is stored or the tag no longer exists.
  Future<(List<UnifiedTagChainItem>, List<UnifiedTagChain>)>
  _reloadSourceTagItems(PresentationGroupRecord group) async {
    final tagKey = group.sourceTagKey?.trim() ?? '';
    final tagId = group.sourceTagId?.trim() ?? '';
    final tagName = group.sourceTagName?.trim() ?? '';

    final colon = tagKey.indexOf(':');
    final parsedKind = colon > 0 ? tagKey.substring(0, colon) : '';
    final parsedName = colon > 0 ? tagKey.substring(colon + 1).trim() : '';

    // Hash tags must use the same ID-generation path as original creation so
    // saved sourceItemIds match the reloaded item IDs for deduplication.
    if (parsedKind == 'hash' && parsedName.isNotEmpty) {
      final preview = await _resolveLegacyHashPreview(
        requestedTagName: parsedName,
      );
      if (preview != null && preview.items.isNotEmpty) {
        return (preview.items, preview.resolvedChains);
      }
    }

    // Adapter path for unified / dollar / unknown storage kinds.
    // Load the snapshot once and do all lookups against it.
    if (tagId.isEmpty && parsedName.isEmpty && tagName.isEmpty) {
      return (const <UnifiedTagChainItem>[], const <UnifiedTagChain>[]);
    }
    final adapter = UnifiedTagReadAdapter();
    final snapshot = await adapter.loadSnapshot();

    // Try exact chain ID match first (most precise).
    if (tagId.isNotEmpty) {
      for (final chain in snapshot.chains) {
        if (chain.id == tagId) return _itemsFromAdapterChain(chain);
      }
    }

    // Name-based fallback.
    final lookupName = parsedName.isNotEmpty ? parsedName : tagName;
    if (lookupName.isNotEmpty) {
      final matching = snapshot.chains.where((chain) {
        if (!(_tagMatches(chain.name, lookupName) ||
            _tagMatches(chain.legacyTagName, lookupName))) {
          return false;
        }
        return chain.storageKind != UnifiedTagStorageKind.dollar;
      }).toList()..sort(_compareChainPriority);
      if (matching.isNotEmpty) return _itemsFromAdapterChain(matching.first);
    }

    return (const <UnifiedTagChainItem>[], const <UnifiedTagChain>[]);
  }

  (List<UnifiedTagChainItem>, List<UnifiedTagChain>) _itemsFromAdapterChain(
    UnifiedTagChain chain,
  ) {
    final items =
        chain.items.where((item) => !item.isDeleted).toList(growable: false)
          ..sort(_comparePreviewItems);
    return (_expandPresentationItems(items), [chain]);
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
    // Only use image/media as the base type for pure-media entries (no text
    // content, no bible anchor). When an entry has both media and text/verse
    // content, use the text-based type so _expandPresentationItems can create
    // independent image items that the user can place in separate zones.
    final hasTextContent =
        (entry.noteText?.trim() ?? '').isNotEmpty ||
        (entry.contentHtml?.trim() ?? '').isNotEmpty;
    final isBibleAnchor =
        entry.bookNumber > 0 && entry.chapter > 0 && entry.verse > 0;
    final itemType = hasMedia && !hasTextContent && !isBibleAnchor
        ? (media.every((m) => m.mediaType.toLowerCase().startsWith('image/'))
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
      fontScale: _fontScale,
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

  Future<void> _savePresentation() async {
    final workspace = _workspace;
    if (workspace == null) return;
    final String defaultName;
    if (_editMode) {
      defaultName = widget.editPresentation!.name;
    } else {
      final rawTag = workspace.requestedTagName.trim();
      final tag = rawTag.startsWith('#') ? rawTag.substring(1) : rawTag;
      defaultName = tag.isNotEmpty ? tag : 'Untitled Presentation';
    }
    final name = await _showSaveNameDialog(
      defaultName: defaultName,
      title: _editMode ? 'Update Presentation' : 'Save Presentation',
      confirmLabel: _editMode ? 'Update' : 'Save',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      final request = await _buildSaveRequest(
        name: name.trim(),
        workspace: workspace,
      );
      await PresentationPrepRepository.instance.savePresentation(request);
      if (_editMode) {
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        _showSnack('Presentation "${name.trim()}" saved.');
      }
    } catch (_) {
      await _showErrorDialog(
        'Could not save the presentation.',
        title: 'Save failed',
      );
    }
  }

  Future<void> _openSavedPresentations() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TagSavedPresentationsScreen(),
      ),
    );
  }

  Future<String?> _showSaveNameDialog({
    required String defaultName,
    String title = 'Save Presentation',
    String confirmLabel = 'Save',
  }) async {
    if (!mounted) return null;
    final controller = TextEditingController(text: defaultName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Presentation name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<PresentationSaveRequest> _buildSaveRequest({
    required String name,
    required TagPresentationPrepWorkspace workspace,
  }) async {
    final bibleBodyById = await _preloadBibleBodies(workspace);
    final firstChain = workspace.resolvedChains.isNotEmpty
        ? workspace.resolvedChains.first
        : null;
    final editGroup = _editGroupRecord;
    final sourceTagId = firstChain?.id ?? editGroup?.sourceTagId;
    final sourceTagKey = firstChain != null
        ? '${firstChain.storageKind.name}:${firstChain.name}'
        : editGroup?.sourceTagKey;
    final sourceTagNameStr = workspace.requestedTagName.trim();
    final sourceTagName = sourceTagNameStr.isNotEmpty
        ? sourceTagNameStr
        : editGroup?.sourceTagName;
    return PresentationSaveRequest(
      name: name,
      sourceTagId: sourceTagId,
      sourceTagKey: sourceTagKey,
      sourceTagName: sourceTagName,
      defaultDisplayTarget: workspace.slides.isNotEmpty
          ? workspace.slides.first.aspectRatio.preset.name
          : null,
      slides: [
        for (var i = 0; i < workspace.slides.length; i++)
          _buildSlideSaveRequest(
            workspace.slides[i],
            i,
            workspace.itemsById,
            bibleBodyById,
          ),
      ],
    );
  }

  /// Pre-loads verse text from the Bible DB for any Bible verse/range item that
  /// has a [bibleAnchor] but no [textSnapshot]. This ensures [bodyOverride] is
  /// populated in the saved DB record so playback can render the verse without
  /// a live DB lookup (which requires a reconstructed bibleAnchor).
  Future<Map<String, String>> _preloadBibleBodies(
    TagPresentationPrepWorkspace workspace,
  ) async {
    final result = <String, String>{};
    for (final item in workspace.items) {
      if (item.itemType != UnifiedTagItemType.bibleVerse &&
          item.itemType != UnifiedTagItemType.bibleRange) {
        continue;
      }
      if ((item.textSnapshot ?? '').trim().isNotEmpty) continue;
      final bible = item.bibleAnchor;
      if (bible == null) continue;
      final start = bible.verseStart;
      final end = bible.verseEnd < start ? start : bible.verseEnd;
      if (start <= 0) continue;
      final verses = <String>[];
      for (var verse = start; verse <= end; verse++) {
        final text = await StudyBibleDatabase.instance.loadVerseText(
          bookNumber: bible.bookNumber,
          chapter: bible.chapter,
          verse: verse,
        );
        final cleaned = (text ?? '').trim();
        if (cleaned.isNotEmpty) verses.add(cleaned);
      }
      if (verses.isNotEmpty) result[item.id] = verses.join('\n');
    }
    return result;
  }

  PresentationSlideSaveRequest _buildSlideSaveRequest(
    TagPresentationPrepSlide slide,
    int slideOrder,
    Map<String, UnifiedTagChainItem> itemsById,
    Map<String, String> bibleBodyById,
  ) {
    final zones = <PresentationZoneSaveRequest>[];
    for (final region in slide.gridLayout.sortedMergedRegions) {
      final zoneKey = 'merge:${region.id}';
      zones.add(
        PresentationZoneSaveRequest(
          zoneKey: zoneKey,
          zoneType: 'merged',
          startRow: region.startRow,
          startColumn: region.startColumn,
          rowSpan: region.rowSpan,
          columnSpan: region.columnSpan,
          items: [
            for (var j = 0; j < region.itemIds.length; j++)
              _buildItemSaveRequest(
                j,
                itemsById[region.itemIds[j]],
                bibleBodyById,
              ),
          ],
        ),
      );
    }
    for (final cell in slide.gridLayout.visibleCells) {
      final zoneKey = 'cell:${cell.row}:${cell.column}';
      zones.add(
        PresentationZoneSaveRequest(
          zoneKey: zoneKey,
          zoneType: 'cell',
          startRow: cell.row,
          startColumn: cell.column,
          rowSpan: 1,
          columnSpan: 1,
          items: [
            for (var j = 0; j < cell.itemIds.length; j++)
              _buildItemSaveRequest(
                j,
                itemsById[cell.itemIds[j]],
                bibleBodyById,
              ),
          ],
        ),
      );
    }
    return PresentationSlideSaveRequest(
      slideOrder: slideOrder,
      title: slide.label,
      topHeaderText: slide.topHeaderText,
      bottomFooterText: slide.bottomFooterText,
      displayTarget: slide.aspectRatio.label,
      aspectRatioPreset: slide.aspectRatio.preset.name,
      aspectRatioValue: slide.aspectRatio.aspectRatio,
      rows: slide.gridLayout.rows,
      columns: slide.gridLayout.columns,
      zones: zones,
    );
  }

  PresentationItemSaveRequest _buildItemSaveRequest(
    int order,
    UnifiedTagChainItem? item,
    Map<String, String> bibleBodyById,
  ) {
    final existingSnapshot = item?.textSnapshot?.trim() ?? '';
    final bodyOverride = existingSnapshot.isNotEmpty
        ? item!.textSnapshot
        : (item?.id != null ? bibleBodyById[item!.id] : null);
    return PresentationItemSaveRequest(
      itemOrder: order,
      sourceItemId: item?.id,
      itemType: item?.itemType.name,
      titleOverride: item?.displayTitle,
      bodyOverride: bodyOverride,
      mediaPath: item?.media.isNotEmpty == true
          ? item!.media.first.relativePath
          : null,
      mediaCaption: item?.media.isNotEmpty == true
          ? item!.media.first.caption
          : null,
    );
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
        // Expanded image/media items render ONLY their assigned media in the
        // zone. Text content and anchors from the parent are intentionally
        // omitted so note text never leaks into image zones and vice-versa.
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
            textSnapshot: null,
            noteText: null,
            htmlContent: null,
            media: [media],
            bibleAnchor: null,
            elibraryAnchor: null,
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
    // Use an explicit user-provided caption when available and not internal.
    final caption = _cleanText(media.caption);
    if (caption != null && !_isInternalMediaLabel(caption)) {
      return isImage ? 'Image: $caption' : 'Media: $caption';
    }
    // Never expose raw filenames, hashes, or internal paths.
    return isImage ? 'Attached image' : 'Attached media';
  }

  bool _isInternalMediaLabel(String value) {
    final lower = value.toLowerCase();
    if (lower.startsWith('content_') ||
        lower.startsWith('media_') ||
        lower.startsWith('file_') ||
        lower.startsWith('img_')) {
      return true;
    }
    if (value.contains('/') || value.contains('\\')) {
      return true;
    }
    if (RegExp(r'content_\d{7,}').hasMatch(lower)) {
      return true;
    }
    if (!value.contains(' ') &&
        value.length > 20 &&
        RegExp(r'\.(png|jpg|jpeg|gif|webp|bmp|heic)$').hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'^[a-f0-9]{12,}$', caseSensitive: false).hasMatch(value)) {
      return true;
    }
    return false;
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
      appBar: AppBar(
        title: Text(
          _editMode ? 'Edit Presentation' : 'Presentation Preparation',
        ),
      ),
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
                      fontScale: _fontScale,
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
                              _HeaderCard(
                                tagName: requestedTag,
                                fontScale: _fontScale,
                                isEditMode: _editMode,
                              ),
                              const SizedBox(height: 12),
                              if (workspace == null)
                                TagPresentationPrepEmptyState(
                                  title: 'No workspace loaded',
                                  message:
                                      'Open this screen from a #tag detail view.',
                                  hint:
                                      'The selected #tag name is passed into this screen.',
                                  fontScale: _fontScale,
                                )
                              else
                                _PresentationPrepWorkspaceLayout(
                                  workspace: workspace,
                                  mediaRootPath: _mediaRootPath,
                                  viewportHeight: viewportHeight,
                                  fontScale: _fontScale,
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
                                  onSavePresentation: _savePresentation,
                                  onSavedPresentations: _openSavedPresentations,
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
  const _HeaderCard({
    required this.tagName,
    required this.fontScale,
    this.isEditMode = false,
  });

  final String tagName;
  final double fontScale;
  final bool isEditMode;

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
              isEditMode ? 'Edit Presentation' : 'Presentation Preparation',
              style: presentationTextStyle(
                context,
                theme.textTheme.headlineSmall,
                fontScale,
                fontWeight: FontWeight.w700,
                minFontSize: 22,
                maxFontSize: 30,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${isEditMode ? "Editing" : "Preparing"}: $tagName',
              style: presentationTextStyle(
                context,
                theme.textTheme.titleMedium,
                fontScale,
                minFontSize: 17,
                maxFontSize: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isEditMode
                  ? 'Make changes to slides, then tap Update to save.'
                  : 'Use Choose Card to place cards, edit the slide frame above, and preview when ready.',
              style: presentationTextStyle(
                context,
                theme.textTheme.bodyMedium,
                fontScale,
                minFontSize: 14,
                maxFontSize: 18,
              ),
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
    required this.fontScale,
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
    required this.onSavePresentation,
    required this.onSavedPresentations,
  });

  final TagPresentationPrepWorkspace workspace;
  final String? mediaRootPath;
  final double viewportHeight;
  final double fontScale;
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
  final VoidCallback onSavePresentation;
  final VoidCallback onSavedPresentations;

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
            : math.min(400.0, math.max(340.0, availableWidth * 0.28));
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
          fontScale: fontScale,
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
          onSavePresentation: onSavePresentation,
          onSavedPresentations: onSavedPresentations,
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
