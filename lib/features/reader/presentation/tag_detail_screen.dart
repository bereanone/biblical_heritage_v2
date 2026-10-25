import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_paste_input/flutter_paste_input.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/study_bible_database.dart';
import '../../../core/theme/app_settings_service.dart';
import '../../library/data/library_catalog_service.dart';
import '../../library/data/library_citation_display_helper.dart';
import '../../library/presentation/library_book_reader_screen.dart';
import '../../library/presentation/library_item_open_guard.dart';
import '../data/presentation/note_image_layout.dart';
import 'note_image_layout_editor.dart';
import 'note_image_clipboard.dart';
import 'note_image_import.dart';
import 'slide_link_control.dart';
import 'tag_entry_actions.dart';
import '../data/presentation/presentation_text_format.dart';
import 'presentation_prep/presentation_ui_helpers.dart';
import 'tag_dialog_styles.dart';
import 'study_export_clipboard.dart';
import 'tag_playback/tag_playback_popup.dart';
import 'tag_quick_apply_helper.dart';
import 'viewer_presentation_launcher.dart';
import 'viewer_presentation_settings.dart';
import 'viewer_search_dialog.dart';

part 'tag_detail_screen_dialogs.dart';

/// Reuses the list's note editor, including for a tag with no entries yet.
Future<bool?> showHashTagNoteEditor(
  BuildContext context, {
  required HashTagRepository repository,
  required String tag,
  String? category,
  required double fontScale,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _ContentItemDialog(
    repository: repository,
    tag: tag,
    category: category,
    fontScale: fontScale,
  ),
);

class HashTagDetailScreen extends StatefulWidget {
  const HashTagDetailScreen({
    super.key,
    required this.repository,
    required this.tag,
    this.category,
    required this.fontScale,
    this.onSelectBlockId,
    this.onSelectTag,
  });

  final HashTagRepository repository;
  final String tag;
  final String? category;
  final double fontScale;
  final Future<void> Function(int blockId)? onSelectBlockId;
  final Future<void> Function(String tag)? onSelectTag;

  @override
  State<HashTagDetailScreen> createState() => _HashTagDetailScreenState();
}

class _HashTagDetailScreenState extends State<HashTagDetailScreen> {
  final Map<int, String> _bookNames = <int, String>{};
  bool _loading = true;
  String? _defaultTag;
  String? _currentCategory;
  List<HashTagEntry> _entries = const <HashTagEntry>[];
  int _focusedIndex = 0;
  bool _hasChanges = false;
  String? _feedbackMessage;

  @override
  void initState() {
    super.initState();
    _currentCategory = widget.category?.trim().isNotEmpty == true
        ? widget.category!.trim()
        : null;
    _load();
  }

  String? get _resolvedCategory {
    final category = _currentCategory?.trim() ?? '';
    return category.isEmpty ? null : category;
  }

  Future<void> _load() async {
    final defaultTag = await widget.repository.loadDefaultTag();
    final entries = await widget.repository.loadEntries(
      widget.tag,
      category: _resolvedCategory,
      sortMode: HashTagEntrySortMode.slideOrder,
    );
    final books = await StudyBibleDatabase.instance.loadBooks();
    final names = {for (final book in books) book.bookNumber: book.bookName};
    if (!mounted) return;
    setState(() {
      _defaultTag = defaultTag;
      _entries = entries;
      _focusedIndex = entries.isEmpty
          ? 0
          : _focusedIndex.clamp(0, entries.length - 1);
      _bookNames
        ..clear()
        ..addAll(names);
      _loading = false;
    });
  }

  Future<void> _findTextForThisList() async {
    await showViewerSearchDialog(
      context,
      fontScale: widget.fontScale,
      currentTag: widget.tag,
      onBibleResultAdded: (_) async {
        if (!mounted) return;
        _markChanged();
        await _reload();
        await _notifyParentChanged();
      },
    );
  }

  Future<void> _reload() async {
    final entries = await widget.repository.loadEntries(
      widget.tag,
      category: _resolvedCategory,
      sortMode: HashTagEntrySortMode.slideOrder,
    );
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _focusedIndex = entries.isEmpty
          ? 0
          : _focusedIndex.clamp(0, entries.length - 1);
    });
  }

  void _markChanged() {
    _hasChanges = true;
  }

  Future<void> _notifyParentChanged() async {
    final onSelectTag = widget.onSelectTag;
    if (onSelectTag == null) return;
    await onSelectTag(widget.tag);
  }

  void _closeDetail() {
    Navigator.of(context).pop(_hasChanges);
  }

  bool get _isDollarRepository => widget.repository is DollarTagRepository;

  void _listenToTag() => showTagPlaybackPopup(
    context,
    tag: widget.tag,
    category: _resolvedCategory,
    isDollar: _isDollarRepository,
    fontScale: widget.fontScale,
  );

  bool _isNoteOnlyEntry(HashTagEntry entry) {
    return entry.bookNumber == 0 &&
        entry.chapter == 0 &&
        entry.verse == 0 &&
        entry.verseRef.startsWith('note:');
  }

  String _friendlyTagName() {
    return widget.tag.replaceFirst(RegExp(r'^[#\$@]+'), '');
  }

  int _noteOnlyIndexOf(HashTagEntry entry) {
    var count = 0;
    for (final e in _entries) {
      if (_isNoteOnlyEntry(e)) count++;
      if (e.id == entry.id) return count;
    }
    return 1;
  }

  String _friendlyNoteLabel(HashTagEntry entry) {
    final userTitle = entry.userTitle?.trim() ?? '';
    if (userTitle.isNotEmpty) return userTitle;
    return '${_friendlyTagName()} Note ${_noteOnlyIndexOf(entry)}';
  }

  bool _hasEntryNote(HashTagEntry entry) {
    if (_isDollarRepository) {
      return entry.contentHtml?.trim().isNotEmpty == true;
    }
    return entry.noteText?.trim().isNotEmpty == true;
  }

  String _entryNoteText(HashTagEntry entry) {
    if (_isDollarRepository) {
      return _cleanStoredHtml(entry.contentHtml ?? '').trim();
    }
    return entry.noteText?.trim() ?? '';
  }

  int? _bookNumberForName(String rawBook) {
    final normalized = _normalizeBookKey(rawBook);
    for (final entry in _bookNames.entries) {
      if (_normalizeBookKey(entry.value) == normalized) return entry.key;
    }
    return null;
  }

  String _cleanStoredHtml(String input) {
    return input
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  String _plainTextToHtml(String input) {
    final text = input.trim();
    if (text.isEmpty) return '<p></p>';
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '<p>${escaped.replaceAll('\n', '<br>')}</p>';
  }

  String _normalizeBookKey(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  late final Future<String?> _thumbnailBasePath = _mediaBasePath();

  Widget _mediaThumbnails(HashTagEntry entry) => FutureBuilder<String?>(
    future: _thumbnailBasePath,
    builder: (context, snapshot) {
      final root = snapshot.data;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (var index = 0; index < entry.mediaRefs.length; index++)
          Semantics(
            label: 'Attached image ${index + 1}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(width: 64, height: 64,
                child: root == null
                    ? const Icon(Icons.image_outlined)
                    : Image.file(File(p.isAbsolute(entry.mediaRefs[index])
                        ? entry.mediaRefs[index]
                        : p.join(root, p.normalize(entry.mediaRefs[index]))),
                      fit: BoxFit.contain, cacheWidth: 192,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
      ]);
    },
  );

  Future<String?> _mediaBasePath() async {
    final libraryRoot = await LibraryRootService.instance.libraryRootPath();
    if (libraryRoot != null && libraryRoot.trim().isNotEmpty) {
      return libraryRoot;
    }
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'studybible_media');
  }

  String _mimeTypeForMediaPath(String relativePath) {
    return switch (p.extension(relativePath).toLowerCase()) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      _ => 'image/png',
    };
  }

  Future<List<_StagedMediaAttachment>> _loadMediaAttachmentsForRefs(
    List<String> mediaRefs,
  ) async {
    final attachments = <_StagedMediaAttachment>[];
    final basePath = await _mediaBasePath();
    if (basePath == null || basePath.trim().isEmpty) return attachments;
    for (final mediaRef in mediaRefs) {
      final normalized = mediaRef.trim();
      if (normalized.isEmpty) continue;
      final path = p.isAbsolute(normalized)
          ? normalized
          : p.join(basePath, p.normalize(normalized));
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        attachments.add(
          _StagedMediaAttachment(
            bytes: bytes,
            mimeType: _mimeTypeForMediaPath(normalized),
          ),
        );
      } catch (_) {
        // Skip unreadable media and let the edit dialog proceed.
      }
    }
    return attachments;
  }

  Future<void> _makeDefault() async {
    final currentCategory =
        _resolvedCategory ??
        await widget.repository.loadTagCategory(widget.tag);
    await widget.repository.saveDefaultTag(widget.tag);
    await widget.repository.saveDefaultTagCategory(currentCategory);
    await AppSettingsService.instance.saveActiveTagFamily(
      _isDollarRepository ? 'dollar' : 'hash',
    );
    if (!mounted) return;
    setState(() => _defaultTag = widget.tag);
    final onSelectTag = widget.onSelectTag;
    if (onSelectTag != null) {
      await onSelectTag(widget.tag);
    }
  }

  Future<void> _showInstructions() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('How this screen works'),
          content: const SingleChildScrollView(child: Text(
            'Editing tip: Editing is also possible in landscape mode for additional room. Entry buttons use compact labels on phones and single-line labels on tablet-sized screens when enough space is available. Button text stays limited as reading text gets larger; on very narrow screens, the buttons wrap so every action remains visible.\n\n'
            'Listen opens this list’s audio controls; the clock there opens its listening schedule. '
            'Present opens your slides. The magnifying glass beside the entry count finds Bible text to add directly to this list. Add entry adds a note or content item.\n\n'
            'In List settings, Folder lets you move this list to an existing folder or use Add new folder, enter its name, and choose Move. List settings includes the display aspect ratio. Change it once to resize all Bible, note, and image slides in this list for a different projector. '
            'Export list copies the study for pasting into Word, including note formatting. List settings, the default list setting, and Delete list are visible in the header.\n\n'
            'Edit a Bible entry to change its optional title, display citation, passage, and your note. '
            'Select words before using Bold, Italic, or Underline. Reset restores the original passage and removes its formatting. '
            'Alignment icons beside each text field offer Left, Center, Right, and Justified. Header/footer controls are inside Image Layout. Citations appear below Bible passages and default to right alignment. Unnamed Bible passages have no title above.\n\n'
            'More options contains image attachments. Use Copy Image on a thumbnail, or right-click/long-press it, then use Paste Image in the destination note. Copying retains the original; removing an attachment takes effect when you Save. Image Layout lets you tap cells to select a solid rectangular image area; tap again to deselect. Rows and columns change the grid. Display size comes from List settings and applies to every slide, including Bible passages. Fill selected area may crop image edges; turn it off to show the whole image. Optional header/footer text uses space above/below the note. Text automatically fits around the image; the preview matches presentation proportions. Choose Use layout, then Save. Cancel leaves the note unchanged. Saving edits the entry, not the Bible source.\n\n'
            'Use the up and down arrows on each row to change its order. Use the Link with next ON/OFF switch to combine adjacent entries on one slide; ON names the following entry sharing its slide; keep linking to extend the group. Turning a link off ends that group. Notes with images always get their own slide; linking is unavailable on them and immediately before them.\n\n'
            'Recover an entry from Trash: close this list to return to the # Tags screen, choose View Trash, tap the entry you want, and choose Restore to original tag. '
            'Restore/Move to another tag lets you choose a different destination instead.',
          )),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: TagDialogStyles.fittedButtonLabel('Done'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editCurrentLink() async {
    final entry = _focusedEntry;
    if (entry == null) return;
    final refController = TextEditingController(
      text: _isNoteOnlyEntry(entry)
          ? ''
          : '${_bookNames[entry.bookNumber] ?? 'Book ${entry.bookNumber}'} ${entry.chapter}:${entry.verse}',
    );
    final noteController = TextEditingController(
      text: _cleanStoredHtml(entry.contentHtml ?? ''),
    );
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Current Link'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: refController,
                    decoration: const InputDecoration(
                      labelText: 'Scripture (optional)',
                      hintText: 'Revelation 4:3',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteController,
                    minLines: 6,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: 'Study Note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    refController.dispose();
    noteController.dispose();
    if (shouldSave != true) return;

    final refText = refController.text.trim();
    final noteHtml = _plainTextToHtml(noteController.text);
    if (refText.isEmpty && noteHtml == '<p></p>') {
      _showSnack('Add a scripture reference, a note, or both.');
      return;
    }

    var bookNumber = 0;
    var chapter = 0;
    var verse = 0;
    var verseRef = entry.verseRef;
    if (refText.isNotEmpty) {
      final match = RegExp(r'^(.+?)\s+(\d+)\s*:\s*(\d+)$').firstMatch(refText);
      if (match == null) {
        _showSnack('Could not parse scripture reference: $refText');
        return;
      }
      final rawBook = match.group(1)?.trim() ?? '';
      chapter = int.tryParse(match.group(2) ?? '') ?? 0;
      verse = int.tryParse(match.group(3) ?? '') ?? 0;
      final resolvedBookNumber = _bookNumberForName(rawBook);
      if (resolvedBookNumber == null || chapter <= 0 || verse <= 0) {
        _showSnack('Could not resolve scripture reference: $refText');
        return;
      }
      final blockId = await StudyBibleDatabase.instance.loadBlockIdForVerse(
        bookNumber: resolvedBookNumber,
        chapter: chapter,
        verse: verse,
      );
      if (blockId == null) {
        _showSnack('Verse not found: $refText');
        return;
      }
      bookNumber = resolvedBookNumber;
      verseRef = '$bookNumber:$chapter:$verse';
    } else {
      verseRef = 'note:${entry.id}';
    }

    await widget.repository.updateEntry(
      id: entry.id,
      normalized: entry.isNormalized,
      values: {
        'verse_ref': verseRef,
        'book_number': bookNumber,
        'chapter_number': chapter,
        'verse_number': verse,
        'content_html': noteHtml,
      },
    );
    if (!mounted) return;
    _markChanged();
    await _notifyParentChanged();
    await _reload();
  }

  Future<void> _addNoteSlide() async {
    if (!_isDollarRepository) return;
    final noteController = TextEditingController();
    final referenceController = TextEditingController();
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Note Slide'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: referenceController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Reference Code',
                    hintText: 'Optional, for example GC 623.2',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  autofocus: true,
                  minLines: 6,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: 'Slide Note',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    referenceController.dispose();
    noteController.dispose();
    if (shouldSave != true) return;
    final clean = _plainTextToHtml(noteController.text);
    final referenceCode = referenceController.text.trim();
    if (clean == '<p></p>') {
      _showSnack('Add note content for the slide.');
      return;
    }
    await widget.repository.insertNoteSlide(
      tag: widget.tag,
      contentHtml: clean,
      referenceCode: referenceCode,
      category: _resolvedCategory,
    );
    if (!mounted) return;
    _markChanged();
    await _notifyParentChanged();
    await _reload();
    setState(() {
      _focusedIndex = _entries.isEmpty ? 0 : _entries.length - 1;
    });
  }

  Future<void> _showListSettings() async {
    var preset=await AppSettingsService.instance.loadTagPresentationAspectRatioPreset(tagFamily:_isDollarRepository?'dollar':'hash',tag:widget.tag);
    if(!mounted)return;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder:(context, updateSettings)=>AlertDialog(
        title: const Text('List settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('List name'),
              subtitle: Text(widget.tag),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () {
                Navigator.of(dialogContext).pop();
                _renameTag();
              },
            ),
            ListTile(
              title: const Text('Folder'),
              subtitle: Text(_resolvedCategory ?? 'None'),
              trailing: const Icon(Icons.arrow_drop_down),
              onTap: () {
                Navigator.of(dialogContext).pop();
                _changeCategory();
              },
            ),
            ListTile(title:const Text('Display aspect ratio'),subtitle:const Text('Applies to every slide in this list')),
            DropdownButton<PresentationAspectRatioPreset>(value:preset,isExpanded:true,
              items:[for(final value in PresentationAspectRatioPreset.values) DropdownMenuItem(value:value,child:Text(value.label))],
              onChanged:(value) async {
                if(value==null)return;
                try {
                  await AppSettingsService.instance.saveTagPresentationAspectRatioPreset(tagFamily:_isDollarRepository?'dollar':'hash',tag:widget.tag,preset:value);
                  if(context.mounted)updateSettings((){preset=value;error=null;});
                }catch(_){if(context.mounted)updateSettings(()=>error='Could not save the display size. Please try again.');}
              }),
            if(error!=null) Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      )),
    );
  }

  Future<void> _renameTag() async {
    final renamed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _RenameTagDialog(initialTag: widget.tag),
    );
    final normalized = widget.repository.normalizeTagName(renamed ?? '');
    if (normalized.isEmpty || normalized == widget.tag) return;
    final count = await widget.repository.renameTag(
      oldTag: widget.tag,
      newTag: normalized,
      category: _resolvedCategory,
      categoryKnown: true,
    );
    if (!mounted) return;
    if (count == 0) {
      _showSnack('$normalized already exists. Choose a different tag name.');
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _changeCategory() async {
    final currentCategory = _resolvedCategory;
    final chosenCategory = await showDialog<_MoveTagCategoryResult>(
      context: context,
      builder: (dialogContext) => _MoveTagCategoryDialog(
        repository: widget.repository,
        tag: widget.tag,
        currentCategory: currentCategory,
        fontScale: widget.fontScale,
      ),
    );
    if (!mounted) return;
    final normalizedTarget = chosenCategory?.targetCategory?.trim();
    if (chosenCategory == null) return;
    if ((currentCategory ?? '').toLowerCase() ==
        (normalizedTarget ?? '').toLowerCase()) {
      return;
    }
    if (chosenCategory.merged) {
      _markChanged();
      await _notifyParentChanged();
      await _reload();
      final targetLabel = normalizedTarget?.isNotEmpty == true
          ? normalizedTarget!
          : 'None';
      final sourceLabel = currentCategory?.trim().isNotEmpty == true
          ? currentCategory!.trim()
          : 'None';
      if (chosenCategory.addedCount > 0) {
      } else {
      }
      debugPrint(
        'Merge copy only completed for ${widget.tag}: '
        'source=$sourceLabel target=$targetLabel '
        'added=${chosenCategory.addedCount} skipped=${chosenCategory.skippedCount}',
      );
      return;
    }
    final targetLabel = normalizedTarget?.isNotEmpty == true
        ? normalizedTarget!
        : 'None';
    final sourceLabel = currentCategory?.trim().isNotEmpty == true
        ? currentCategory!.trim()
        : 'None';

    final saved = await widget.repository.saveTagCategory(
      widget.tag,
      normalizedTarget ?? '',
      currentCategory: currentCategory,
      currentCategoryKnown: true,
    );
    if (!mounted) return;
    if (!saved) {
      final sourceEntries = await widget.repository.loadEntries(
        widget.tag,
        category: currentCategory,
      );
      final targetEntries = await widget.repository.loadEntries(
        widget.tag,
        category: normalizedTarget,
      );
      debugPrint(
        'Move category failed for ${widget.tag}: '
        'source=$sourceLabel target=$targetLabel '
        'sourceRows=${sourceEntries.length} targetRows=${targetEntries.length}',
      );
      debugPrint(
        await widget.repository.debugTagReport(
          widget.tag,
          category: currentCategory,
        ),
      );
      _showSnack('Could not move ${widget.tag} to $targetLabel.');
      return;
    }
    setState(() {
      _currentCategory = normalizedTarget;
    });
    _markChanged();
    await _notifyParentChanged();
    await _reload();
    if (_defaultTag == widget.tag) {
      await widget.repository.saveDefaultTagCategory(normalizedTarget);
    }
  }

  final _trashingEntries = <String>{};

  Future<void> _trashEntry(HashTagEntry entry) async {
    final key = '${entry.isNormalized}:${entry.id}';
    if (!_trashingEntries.add(key)) return;
    try {
      await widget.repository.deleteEntry(
        entry.id,
        normalized: entry.isNormalized,
      );
      if (!mounted) return;
      _markChanged();
      await _notifyParentChanged();
      await _reload();
      if (!mounted) return;
    } finally {
      _trashingEntries.remove(key);
    }
  }

  Future<void> _moveEntry(HashTagEntry entry, int delta) async {
    final changed = await widget.repository.moveEntry(
      tag: widget.tag,
      category: _resolvedCategory,
      entryId: entry.id,
      delta: delta,
    );
    if (!mounted || !changed) return;
    _markChanged();
    await _notifyParentChanged();
    await _reload();
  }

  Future<void> _deleteTag() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete entire tag?'),
          content: Text(
            'Delete ${widget.tag} and all ${_entries.length} attached item(s)? '
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: TagDialogStyles.fittedButtonLabel('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: TagDialogStyles.fittedButtonLabel('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await widget.repository.deleteTag(widget.tag, category: _resolvedCategory);
    if (_defaultTag == widget.tag) {
      await widget.repository.clearDefaultTag();
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _openVerse(HashTagEntry entry) async {
    final onSelectBlockId = widget.onSelectBlockId;
    if (onSelectBlockId == null) return;
    final blockId = await StudyBibleDatabase.instance.loadBlockIdForVerse(
      bookNumber: entry.bookNumber,
      chapter: entry.chapter,
      verse: entry.verse,
    );
    if (!mounted || blockId == null) return;
    Navigator.of(context).pop();
    await onSelectBlockId(blockId);
  }

  Future<void> _openPresentationMode() async {
    if (_entries.isEmpty) return;
    await showPresentationLaunchOptions(
      context,
      entries: _entries,
      initialIndex: _focusedIndex,
      tag: widget.tag,
      tagFamily: _isDollarRepository ? 'dollar' : 'hash',
    );
  }

  Future<void> _exportToClipboard() async {
    if (_entries.isEmpty) return;
    final richLines = <int, String>{};
    final lines = <String>[
      'Shared from the Biblical Heritage #StudyBible app.',
      '',
      'For instructions on using the app, visit BiblicalHeritage.net.',
      '',
      '${widget.tag} (${_entries.length} item${_entries.length == 1 ? '' : 's'})',
      '',
    ];

    for (final entry in _entries) {
      // Note-only cards (standalone notes and image-only items)
      if (_isNoteOnlyEntry(entry)) {
        final noteLabel = _friendlyNoteLabel(entry);
        lines.add(noteLabel);
        for (final _ in entry.mediaRefs) {
          lines.add('[Image: $noteLabel image]');
        }
        final noteText = _entryNoteText(entry).trim();
        if (noteText.isNotEmpty) {
          richLines[lines.length] = studyExportHtml(noteText, formatJson: entry.noteFormatJson);
          lines.add(noteText);
        }
        lines.add('');
        continue;
      }

      // eLibrary cards
      final metadata = _eLibraryNoteMetadata(entry);
      if (metadata != null) {
        final title = (_eLibraryNoteTitle(entry) ?? '').trim();
        if (title.isNotEmpty && !title.startsWith('note:')) {
          lines.add(title);
        }
        for (final _ in entry.mediaRefs) {
          final imageLabel = title.isNotEmpty ? '$title image' : 'image';
          lines.add('[Image: $imageLabel]');
        }
        final displayOverride = entry.displayTextOverride?.trim() ?? '';
        final metaExcerpt = metadata.excerpt.trim();
        final metaSelectedText = metadata.selectedTextSnapshot.trim();
        final noteTextValue = entry.noteText?.trim() ?? '';
        final sourceParagraph = metadata.sourceParagraph.trim();
        final excerpt = displayOverride.isNotEmpty
            ? displayOverride
            : metaExcerpt.isNotEmpty
            ? metaExcerpt
            : metaSelectedText.isNotEmpty
            ? metaSelectedText
            : noteTextValue.isNotEmpty
            ? noteTextValue
            : sourceParagraph;
        if (excerpt.isNotEmpty) {
          lines.add('"$excerpt"');
        }
        if (noteTextValue.isNotEmpty && noteTextValue != excerpt) {
          lines.add('Note: ${noteTextValue.replaceAll('\n', ' ')}');
        }
        lines.add('');
        continue;
      }

      // Bible cards
      final bookName =
          _bookNames[entry.bookNumber] ?? 'Book ${entry.bookNumber}';
      final citation = _displayCitationForEntry(entry, bookName: bookName);
      if (citation.isNotEmpty) {
        lines.add(citation);
      }
      for (final _ in entry.mediaRefs) {
        final imageLabel = citation.isNotEmpty ? '$citation image' : 'image';
        lines.add('[Image: $imageLabel]');
      }
      final verseText = (entry.displayTextOverride?.trim().isNotEmpty == true)
          ? entry.displayTextOverride!.trim()
          : entry.numberedVerseText;
      if (verseText.isNotEmpty) {
        richLines[lines.length] = studyExportHtml(verseText,
            formatJson: entry.displayTextOverride?.trim().isNotEmpty == true
                ? entry.displayTextFormatJson : null);
        lines.add(verseText);
      } else {
        final fallback = await loadBibleRangeText(
          bookNumber: entry.bookNumber,
          chapter: entry.chapter,
          verseStart: entry.verse,
          verseEnd: entry.verseEnd,
        );
        final resolvedText = formatBibleRangeForDisplay(
          fallback,
          verseStart: entry.verse,
          verseEnd: entry.verseEnd,
        );
        if (resolvedText.isNotEmpty) {
          lines.add(resolvedText);
        }
      }
      final noteText = _entryNoteText(entry).trim();
      if (noteText.isNotEmpty) {
        richLines[lines.length] = 'Note: ${studyExportHtml(noteText, formatJson: entry.noteFormatJson)}';
        lines.add('Note: ${noteText.replaceAll('\n', ' ')}');
      }
      lines.add('');
    }

    await copyStudyExport(
      text: lines.join('\n').trimRight(),
      html: List.generate(lines.length, (index) =>
          '<div>${richLines[index] ?? studyExportHtml(lines[index])}</div>').join(),
    );
    if (!mounted) return;
  }

  void _showSnack(String message) {
    if (mounted) setState(() => _feedbackMessage = message);
  }

  HashTagEntry? get _focusedEntry {
    if (_entries.isEmpty) return null;
    return _entries[_focusedIndex.clamp(0, _entries.length - 1)];
  }

  String _entryTitle(HashTagEntry entry, String bookName) {
    final eLibraryTitle = _eLibraryNoteTitle(entry)?.trim() ?? '';
    if (eLibraryTitle.isNotEmpty) return eLibraryTitle;
    final referenceCode = _displayCitationForEntry(entry, bookName: bookName);
    final userTitle = entry.userTitle?.trim() ?? '';
    if (userTitle.isNotEmpty) return userTitle;
    if (referenceCode.isNotEmpty) return referenceCode;
    final metadata = _eLibraryNoteMetadata(entry);
    if (metadata != null) return '';
    if (_isNoteOnlyEntry(entry)) {
      return _friendlyNoteLabel(entry);
    }
    final verseLabel = entry.verseEnd > entry.verse
        ? '${entry.verse}-${entry.verseEnd}'
        : '${entry.verse}';
    return '$bookName ${entry.chapter}:$verseLabel';
  }

  String _entryBody(HashTagEntry entry) {
    if (_isNoteOnlyEntry(entry)) {
      final noteText = _entryNoteText(entry);
      if (noteText.isNotEmpty) return noteText;
      if (entry.hasMedia) return 'Image attached';
      return 'Note item';
    }
    final noteHtml = entry.contentHtml?.trim() ?? '';
    final displayOverride = entry.displayTextOverride?.trim() ?? '';
    if (displayOverride.isNotEmpty) {
      if (entry.hasMedia) {
        return '$displayOverride\nImage attached';
      }
      return displayOverride;
    }
    final verseText = entry.numberedVerseText;
    if (verseText.isNotEmpty) {
      if (entry.hasMedia) {
        return '$verseText\nImage attached';
      }
      return verseText;
    }
    if (noteHtml.isNotEmpty) {
      final noteText = _cleanStoredHtml(noteHtml);
      if (noteText.isNotEmpty) return noteText;
    }
    if (entry.hasMedia) {
      return 'Image attached';
    }
    final metadata = _eLibraryNoteMetadata(entry);
    if (metadata != null) {
      final detailText = _eLibraryDetailText(metadata);
      if (detailText.isNotEmpty) return detailText;
      return '';
    }
    if (entry.bookNumber == 0 && entry.verseRef.startsWith('note:')) {
      return 'Note slide';
    }
    return entry.verseRef;
  }

  String _displayCitationForEntry(HashTagEntry entry, {String? bookName}) {
    final direct = entry.referenceCode?.trim() ?? '';
    if (direct.isNotEmpty) return direct;
    if (entry.bookNumber > 0 && entry.chapter > 0 && entry.verse > 0) {
      final resolvedBookName = bookName?.trim() ?? '';
      return bibleRangeReferenceLabel(
        bookName: resolvedBookName.isNotEmpty
            ? resolvedBookName
            : 'Book ${entry.bookNumber}',
        chapter: entry.chapter,
        verseStart: entry.verse,
        verseEnd: entry.verseEnd,
      );
    }
    final verseRef = entry.verseRef.trim();
    if (verseRef.isEmpty || _looksLikeInternalELibraryText(verseRef)) {
      return '';
    }
    if (_looksLikeRawBibleReference(verseRef)) {
      return '';
    }
    if (verseRef.startsWith('note:')) {
      return '';
    }
    return verseRef;
  }

  bool _looksLikeRawBibleReference(String value) {
    return RegExp(r'^\d+:\d+:\d+(?:-\d+)?$').hasMatch(value.trim());
  }

  String? _entryNotePreview(HashTagEntry entry) {
    final note = _entryNoteText(entry);
    if (note.isEmpty) return null;
    const maxLength = 96;
    if (note.length <= maxLength) return note;
    return '${note.substring(0, maxLength - 1)}…';
  }

  String? _eLibraryNoteTitle(HashTagEntry entry) {
    final metadata = _eLibraryNoteMetadata(entry);
    if (metadata == null) return null;
    return libraryUserFacingELibraryDisplayLabel(
      sourceTitle: metadata.sourceTitle,
      sourceTitleAcronym: metadata.sourceTitleAcronym,
      sourceLocation: metadata.sourceLocation,
      sourceReferenceText: metadata.sourceReferenceText,
      fileName: metadata.sourceRelativePath.trim().isNotEmpty
          ? p.basename(metadata.sourceRelativePath)
          : null,
      relativePath: metadata.sourceRelativePath,
      pageCitation: metadata.citationText.isNotEmpty
          ? metadata.citationText
          : null,
      paragraphIndex:
          metadata.sourceParagraphNumber ?? metadata.sourceParagraphIndex,
    );
  }

  String _referenceCodeForEntry(HashTagEntry entry) {
    final direct = entry.referenceCode?.trim() ?? '';
    final safeDirect = _safeELibraryReferenceText(direct);
    if (safeDirect.isNotEmpty) return safeDirect;

    final metadata = _eLibraryNoteMetadata(entry);
    if (metadata == null) return '';
    return libraryUserFacingELibraryCitationText(
      sourceTitle: metadata.sourceTitle,
      sourceTitleAcronym: metadata.sourceTitleAcronym,
      sourceLocation: metadata.sourceLocation,
      sourceReferenceText: metadata.sourceReferenceText,
      fileName: metadata.sourceRelativePath.trim().isNotEmpty
          ? p.basename(metadata.sourceRelativePath)
          : null,
      relativePath: metadata.sourceRelativePath,
      pageCitation: metadata.citationText.isNotEmpty
          ? metadata.citationText
          : null,
      paragraphIndex:
          metadata.sourceParagraphNumber ?? metadata.sourceParagraphIndex,
    );
  }

  String _safeELibraryTitle(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty || _looksLikeInternalELibraryText(cleaned)) {
      return '';
    }
    return cleaned;
  }

  String _safeELibraryReferenceText(String value) {
    return librarySafeUserFacingReferenceText(value) ?? '';
  }

  String _eLibraryDetailText(_ELibraryNoteMetadata metadata) {
    final fileName = metadata.sourceRelativePath.trim().isNotEmpty
        ? p.basename(metadata.sourceRelativePath)
        : '';
    final officialReferenceText =
        librarySafeUserFacingReferenceText(metadata.sourceLocation) != null
        ? metadata.sourceLocation
        : metadata.sourceReferenceText;
    final friendlyLocation = libraryUserFacingSearchLocationText(
      title: metadata.sourceTitle,
      officialReferenceText: officialReferenceText,
      fileName: fileName,
      relativePath: metadata.sourceRelativePath,
      pageCitation: metadata.citationText.isNotEmpty
          ? metadata.citationText
          : null,
      paragraphIndex:
          metadata.sourceParagraphNumber ?? metadata.sourceParagraphIndex,
    );
    if (friendlyLocation.isNotEmpty) return friendlyLocation;

    final safeTitle = _safeELibraryTitle(metadata.sourceTitle);
    if (safeTitle.isNotEmpty) return safeTitle;

    final abbreviation = metadata.sourceTitleAcronym.trim();
    if (abbreviation.isNotEmpty) return abbreviation;

    return '';
  }

  bool _looksLikeInternalELibraryText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return true;
    return trimmed.startsWith('elibrary:') ||
        trimmed.contains('::') ||
        trimmed.toLowerCase().contains('.xhtml') ||
        trimmed.toLowerCase().contains('oebps/');
  }

  _ELibraryNoteMetadata? _eLibraryNoteMetadata(HashTagEntry entry) {
    final raw = entry.noteFormatJson?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['kind']?.toString() != 'elibrary_note') return null;
      return _ELibraryNoteMetadata(
        sourceTitle: decoded['source_title']?.toString() ?? '',
        sourceTitleAcronym: decoded['source_title_acronym']?.toString() ?? '',
        sourceLocation: decoded['source_location']?.toString() ?? '',
        sourceReferenceText: decoded['source_reference_text']?.toString() ?? '',
        sourceHref: decoded['source_href']?.toString() ?? '',
        sourceAnchorId: decoded['source_anchor_id']?.toString() ?? '',
        sourceSpineIndex: _intFromJson(decoded['source_spine_index']),
        sourceParagraphIndex: _intFromJson(decoded['source_paragraph_index']),
        sourceRelativePath: decoded['source_relative_path']?.toString() ?? '',
        sourcePageNumber: _intFromJson(decoded['source_page_number']),
        sourceParagraphNumber: _intFromJson(decoded['source_paragraph_number']),
        searchQuery: decoded['search_query']?.toString() ?? '',
        sourceParagraph: decoded['source_paragraph']?.toString() ?? '',
        excerpt: decoded['excerpt']?.toString() ?? '',
        stableRef: decoded['stable_ref']?.toString() ?? '',
        sourceLibraryItemId:
            decoded['source_library_item_id']?.toString() ?? '',
        selectedTextSnapshot:
            decoded['selected_text_snapshot']?.toString() ?? '',
        selectionStartBlockIndex: _intFromJson(
          decoded['selection_start_block_index'],
        ),
        selectionStartCharOffset: _intFromJson(
          decoded['selection_start_char_offset'],
        ),
        selectionEndBlockIndex: _intFromJson(
          decoded['selection_end_block_index'],
        ),
        selectionEndCharOffset: _intFromJson(
          decoded['selection_end_char_offset'],
        ),
        selectionStartTokenIndex: _intFromJson(
          decoded['selection_start_token_index'],
        ),
        selectionEndTokenIndex: _intFromJson(
          decoded['selection_end_token_index'],
        ),
      );
    } catch (_) {
      return null;
    }
  }

  int? _intFromJson(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  bool _canLinkNext(HashTagEntry entry) {
    final index=_entries.indexWhere((e)=>e.id==entry.id && e.isNormalized==entry.isNormalized);
    if(index<0 || index+1>=_entries.length)return false;
    final next=_entries[index+1];
    return !(_isNoteOnlyEntry(entry)&&entry.hasMedia) && !(_isNoteOnlyEntry(next)&&next.hasMedia);
  }
  final _savingLinks=<String>{};
  Future<void> _setLinkNext(HashTagEntry entry,bool linked) async {
    final key='${entry.isNormalized}:${entry.id}';
    if(!_canLinkNext(entry) || !_savingLinks.add(key))return;
    setState((){});
    try {
      final inner=presentationFormatWithLink(entry.noteFormatJson,linked);
      final format=_isNoteOnlyEntry(entry) ? inner : buildBibleItemOverlayJson(userTitle:entry.userTitle,
        displayTextOverride:entry.displayTextOverride,noteFormatJson:inner,titleFormatJson:entry.titleFormatJson,displayTextFormatJson:entry.displayTextFormatJson);
      await widget.repository.updateEntry(id:entry.id,normalized:entry.isNormalized,values:{
        'note_format_json':format,'presentation_slide_number':null,'presentation_slide_region':null});
      await _reload();
      if(!mounted)return;
      final saved=_entries.where((e)=>e.id==entry.id && e.isNormalized==entry.isNormalized).firstOrNull;
      if(saved==null || presentationLinksWithNext(saved.noteFormatJson)!=linked)throw StateError('Link readback failed');
      _markChanged();await _notifyParentChanged();
    }catch(_){if(mounted)_showSnack('Could not save the slide link. Please try again.');}
    finally{_savingLinks.remove(key);if(mounted)setState((){});}
  }
  Widget _slideLinkControl(HashTagEntry entry) {
    final index=_entries.indexWhere((e)=>e.id==entry.id && e.isNormalized==entry.isNormalized);
    final next=index>=0 && index+1<_entries.length ? _entries[index+1] : null;
    final allowed=_canLinkNext(entry);
    final nextTitle=next==null?null:_entryTitle(next,_bookNames[next.bookNumber]??'');
    return SlideLinkControl(linked:allowed && presentationLinksWithNext(entry.noteFormatJson),
      onChanged:allowed?(value)=>_setLinkNext(entry,value):null,nextTitle:nextTitle,
      saving:_savingLinks.contains('${entry.isNormalized}:${entry.id}'),
      disabledReason:allowed?null:next==null?'Last entry · no following entry.': 'Image notes use their own slide.');
  }

  Future<void> _editEntryNote(HashTagEntry entry) async {
    if (_isDollarRepository) return;
    final currentNote = entry.noteText?.trim() ?? '';
    final currentVerseText = _isNoteOnlyEntry(entry)
        ? ''
        : (entry.verseText.trim().isNotEmpty
              ? entry.verseText.trim()
              : await loadBibleRangeText(
                  bookNumber: entry.bookNumber,
                  chapter: entry.chapter,
                  verseStart: entry.verse,
                  verseEnd: entry.verseEnd,
                ));
    final initialMedia = await _loadMediaAttachmentsForRefs(entry.mediaRefs);
    final presentationAspect = await AppSettingsService.instance.loadTagPresentationAspectRatioPreset(tagFamily:_isDollarRepository?'dollar':'hash',tag:widget.tag);
    if (!mounted) return;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final bookName =
            _bookNames[entry.bookNumber] ?? 'Book ${entry.bookNumber}';
        final canonicalReference = bibleRangeReferenceLabel(
          bookName: bookName,
          chapter: entry.chapter,
          verseStart: entry.verse,
          verseEnd: entry.verseEnd,
        );
        return _EditEntryNoteDialog(
          presentationAspect:presentationAspect,
          repository: widget.repository,
          entry: entry,
          fontScale: widget.fontScale,
          title: _isNoteOnlyEntry(entry)
              ? 'Edit content item'
              : 'Edit Bible range',
          noteLabel: _isNoteOnlyEntry(entry) ? 'Note item' : 'Bible range',
          canonicalReferenceLabel: canonicalReference,
          verseText: currentVerseText,
          initialNoteText: currentNote,
          initialReferenceCode: _isNoteOnlyEntry(entry)
              ? _referenceCodeForEntry(entry)
              : _displayCitationForEntry(entry, bookName: bookName),
          initialUserTitle: entry.userTitle?.trim() ?? '',
          initialTitleFormatJson: entry.titleFormatJson,
          initialDisplayTextOverride: entry.displayTextOverride?.trim() ?? '',
          initialDisplayTextFormatJson: entry.displayTextFormatJson,
          initialNoteFormatJson: entry.noteFormatJson,
          referenceFieldLabel: _isNoteOnlyEntry(entry)
              ? 'User title'
              : 'Display citation',
          referenceFieldHint: _isNoteOnlyEntry(entry)
              ? 'Optional title for this content item'
              : 'Optional citation for this Bible range',
          initialMedia: initialMedia,
        );
      },
    );
    if (shouldSave != true) return;
    if (!mounted) return;
    _markChanged();
    await _notifyParentChanged();
    await _reload();
  }

  Future<void> _addContentItem() async {
    if (_isDollarRepository) return;
    final shouldSave = await showHashTagNoteEditor(
      context,
      repository: widget.repository,
      tag: widget.tag,
      category: _resolvedCategory,
      fontScale: widget.fontScale,
    );
    if (shouldSave != true) return;
    if (!mounted) return;
    _markChanged();
    await _notifyParentChanged();
    await _reload();
    if (!mounted) return;
    setState(() {
      _focusedIndex = _entries.isEmpty ? 0 : _entries.length - 1;
    });
  }

  Future<void> _handleEntryTap(HashTagEntry entry) async {
    if (_isNoteOnlyEntry(entry) && !_isDollarRepository) {
      await _editEntryNote(entry);
      return;
    }
    final metadata = _eLibraryNoteMetadata(entry);
    if (metadata != null && metadata.sourceLibraryItemId.trim().isNotEmpty) {
      final item = await LibraryCatalogService.instance.loadItemById(
        metadata.sourceLibraryItemId.trim(),
      );
      if (item != null) {
        if (!mounted) return;
        if (!await ensureLibraryItemOpenable(context, item)) return;
        if (!mounted) return;
        final navigator = Navigator.of(context, rootNavigator: true);
        navigator.pop();
        await Future<void>.microtask(() {
          if (!navigator.mounted) return;
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => LibraryBookReaderScreen(
                item: item,
                initialHref: metadata.sourceHref.trim().isNotEmpty
                    ? metadata.sourceHref.trim()
                    : item.epubHref,
                initialAnchorId: metadata.sourceAnchorId.trim().isNotEmpty
                    ? metadata.sourceAnchorId.trim()
                    : item.anchorId,
                initialSpineIndex: metadata.sourceSpineIndex ?? item.spineIndex,
                initialParagraphIndex:
                    metadata.sourceParagraphIndex ?? item.paragraphIndex,
              ),
            ),
          );
        });
        return;
      }
      _showSnack(
        'This eLibrary source is no longer available locally, but the card was preserved.',
      );
      return;
    }
    if (metadata != null) {
      _showSnack(
        'This eLibrary card is preserved for reading, but navigation is unavailable.',
      );
      return;
    }
    await _openVerse(entry);
  }

  void _moveFocusedEntry(int delta) {
    if (_entries.isEmpty) return;
    setState(() {
      _focusedIndex = (_focusedIndex + delta).clamp(0, _entries.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleColor = TagDialogStyles.title(theme);
    final bodyColor = TagDialogStyles.body(theme);
    final surface = TagDialogStyles.surface(theme);
    final surfaceHigh = TagDialogStyles.surfaceHigh(theme);
    final cardSurface = TagDialogStyles.card(theme);
    final outlineColor = TagDialogStyles.outlineColor(theme);
    final headerButtonForeground = bodyColor;
    final defaultActive = _defaultTag == widget.tag;
    final focusedEntry = _focusedEntry;

    final headerDecoration = TagDialogStyles.headerDecoration(theme);

    return Material(
      color: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: headerDecoration,
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(widget.tag, style: TagDialogStyles.titleTextStyle(
                                theme, widget.fontScale, color: titleColor,
                                fontWeight: FontWeight.w900)),
                              Text('${_entries.length} entries${_resolvedCategory == null ? '' : ' · $_resolvedCategory'}',
                                style: TagDialogStyles.bodyTextStyle(theme,
                                  widget.fontScale, color: bodyColor)),
                              if (!_isDollarRepository)
                                IconButton(
                                  tooltip: 'Find Bible text to add to this list',
                                  onPressed: _findTextForThisList,
                                  icon: const Icon(Icons.search),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Instructions',
                          onPressed: _showInstructions,
                          icon: const Icon(Icons.help_outline),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: _closeDetail,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HeaderActionChip(
                          icon: Icons.headphones_rounded,
                          label: 'Listen',
                          tooltip: 'Listen to this list',
                          onPressed: _entries.isEmpty ? null : _listenToTag,
                          foregroundColor: headerButtonForeground,
                          phoneCompact: constraints.maxWidth < 700,
                        ),
                        _HeaderActionChip(
                          icon: Icons.slideshow_rounded,
                          label: 'Present',
                          tooltip: 'Present this list',
                          onPressed: focusedEntry == null
                              ? null
                              : _openPresentationMode,
                          foregroundColor: headerButtonForeground,
                          phoneCompact: constraints.maxWidth < 700,
                        ),
                        _HeaderActionChip(
                          icon: Icons.note_add_outlined,
                          label: 'Add entry',
                          tooltip: 'Add entry',
                          onPressed: _isDollarRepository
                              ? _addNoteSlide
                              : _addContentItem,
                          foregroundColor: headerButtonForeground,
                          phoneCompact: constraints.maxWidth < 700,
                        ),
                        _HeaderActionChip(
                          icon: Icons.ios_share,
                          label: 'Export list',
                          tooltip: 'Export list',
                          onPressed: _entries.isEmpty ? null : _exportToClipboard,
                          foregroundColor: headerButtonForeground,
                          phoneCompact: constraints.maxWidth < 700,
                        ),
                        _HeaderActionChip(
                          icon: Icons.settings_outlined,
                          label: 'List settings',
                          tooltip: 'List settings',
                          onPressed: _showListSettings,
                          foregroundColor: headerButtonForeground,
                          phoneCompact: constraints.maxWidth < 700,
                        ),
                        _HeaderActionChip(
                          icon: Icons.star_outline,
                          label: '${defaultActive ? 'Current default list' : 'Set as default list'}',
                          tooltip: 'Default list',
                          onPressed: defaultActive ? null : _makeDefault,
                          foregroundColor: headerButtonForeground,
                          phoneCompact: constraints.maxWidth < 700,
                        ),
                        _HeaderActionChip(
                          icon: Icons.delete_outline,
                          label: 'Delete list',
                          tooltip: 'Delete list',
                          onPressed: _deleteTag,
                          foregroundColor: headerButtonForeground,
                          phoneCompact: constraints.maxWidth < 700,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          if (_feedbackMessage != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_feedbackMessage!, style: TextStyle(
                  color: Theme.of(context).colorScheme.error)),
              ),
            ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                children: [
                  if (focusedEntry != null) ...[
                    if (_isDollarRepository)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: surfaceHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: outlineColor.withValues(alpha: 0.65),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${widget.tag} Study Chain',
                                    style: presentationTextStyle(
                                      context,
                                      theme.textTheme.titleLarge,
                                      widget.fontScale,
                                      color: titleColor,
                                      fontWeight: FontWeight.w900,
                                      minFontSize: 18,
                                      maxFontSize: 28,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _editCurrentLink,
                                  icon: const Icon(Icons.edit_outlined),
                                  label: Text(
                                    'Edit Current Link',
                                    style: presentationTextStyle(
                                      context,
                                      theme.textTheme.labelLarge,
                                      widget.fontScale,
                                      color: bodyColor,
                                      fontWeight: FontWeight.w700,
                                      minFontSize: 13.5,
                                      maxFontSize: 21,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: bodyColor,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    minimumSize: const Size(44, 44),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _focusedIndex > 0
                                      ? () => _moveFocusedEntry(-1)
                                      : null,
                                  icon: const Icon(Icons.chevron_left),
                                  color: bodyColor,
                                  iconSize: presentationScaledSize(
                                    context,
                                    22,
                                    widget.fontScale,
                                    min: 20,
                                    max: 26,
                                  ),
                                  constraints: const BoxConstraints.tightFor(
                                    width: 44,
                                    height: 44,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _entryTitle(
                                      focusedEntry,
                                      _bookNames[focusedEntry.bookNumber] ??
                                          'Book ${focusedEntry.bookNumber}',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: presentationTextStyle(
                                      context,
                                      theme.textTheme.titleLarge,
                                      widget.fontScale,
                                      color: titleColor,
                                      fontWeight: FontWeight.w900,
                                      minFontSize: 18,
                                      maxFontSize: 28,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _focusedIndex < _entries.length - 1
                                      ? () => _moveFocusedEntry(1)
                                      : null,
                                  icon: const Icon(Icons.chevron_right),
                                  color: bodyColor,
                                  iconSize: presentationScaledSize(
                                    context,
                                    22,
                                    widget.fontScale,
                                    min: 20,
                                    max: 26,
                                  ),
                                  constraints: const BoxConstraints.tightFor(
                                    width: 44,
                                    height: 44,
                                  ),
                                ),
                              ],
                            ),
                            if (focusedEntry.bookNumber > 0 &&
                                focusedEntry.verseText.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Current Scripture',
                                textAlign: TextAlign.center,
                                style: presentationTextStyle(
                                  context,
                                  theme.textTheme.labelLarge,
                                  widget.fontScale,
                                  color: titleColor,
                                  fontWeight: FontWeight.w700,
                                  minFontSize: 13.5,
                                  maxFontSize: 21,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                focusedEntry.numberedVerseText,
                                textAlign: TextAlign.center,
                                style: presentationTextStyle(
                                  context,
                                  theme.textTheme.bodyMedium,
                                  widget.fontScale,
                                  color: bodyColor,
                                  height: 1.28,
                                  minFontSize: 15,
                                  maxFontSize: 23,
                                ),
                              ),
                            ],
                            if ((focusedEntry.contentHtml ?? '')
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Study Notes',
                                style: presentationTextStyle(
                                  context,
                                  theme.textTheme.labelLarge,
                                  widget.fontScale,
                                  color: titleColor,
                                  fontWeight: FontWeight.w700,
                                  minFontSize: 13.5,
                                  maxFontSize: 21,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: TagDialogStyles.card(theme),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  _cleanStoredHtml(focusedEntry.contentHtml!),
                                  style: presentationTextStyle(
                                    context,
                                    theme.textTheme.bodyMedium,
                                    widget.fontScale,
                                    color: bodyColor,
                                    height: 1.28,
                                    minFontSize: 15,
                                    maxFontSize: 23,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: surfaceHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: outlineColor.withValues(alpha: 0.65),
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: _focusedIndex > 0
                                  ? () => _moveFocusedEntry(-1)
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                              color: bodyColor,
                              iconSize: presentationScaledSize(
                                context,
                                22,
                                widget.fontScale,
                                min: 20,
                                max: 26,
                              ),
                              constraints: const BoxConstraints.tightFor(
                                width: 44,
                                height: 44,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _entryTitle(
                                  focusedEntry,
                                  _bookNames[focusedEntry.bookNumber] ??
                                      'Book ${focusedEntry.bookNumber}',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: presentationTextStyle(
                                  context,
                                  theme.textTheme.titleLarge,
                                  widget.fontScale,
                                  color: titleColor,
                                  fontWeight: FontWeight.w900,
                                  minFontSize: 18,
                                  maxFontSize: 28,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _focusedIndex < _entries.length - 1
                                  ? () => _moveFocusedEntry(1)
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                              color: bodyColor,
                              iconSize: presentationScaledSize(
                                context,
                                22,
                                widget.fontScale,
                                min: 20,
                                max: 26,
                              ),
                              constraints: const BoxConstraints.tightFor(
                                width: 44,
                                height: 44,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                  ],
                  if (_entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'This tag is empty.',
                        textAlign: TextAlign.center,
                        style: presentationTextStyle(
                          context,
                          theme.textTheme.bodyLarge,
                          widget.fontScale,
                          color: bodyColor,
                          minFontSize: 15,
                          maxFontSize: 23,
                        ),
                      ),
                    )
                  else
                    ..._entries.asMap().entries.map((mapEntry) {
                      final index = mapEntry.key;
                      final entry = mapEntry.value;
                      final bookName =
                          _bookNames[entry.bookNumber] ??
                          'Book ${entry.bookNumber}';
                      final canMoveUp = index > 0;
                      final canMoveDown = index < _entries.length - 1;
                      final hasNote = _hasEntryNote(entry);
                      final citationText = _displayCitationForEntry(
                        entry,
                        bookName: bookName,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: index == _focusedIndex
                                ? surfaceHigh
                                : cardSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: outlineColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              setState(() => _focusedIndex = index);
                              await _handleEntryTap(entry);
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 5,
                                    height: 34,
                                    margin: const EdgeInsets.only(top: 1),
                                    decoration: BoxDecoration(
                                      color: TagDialogStyles.accentStripColor(
                                        theme,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        TagEntryActions(
                                          onEdit: () async {
                                            if (_isDollarRepository) {
                                              setState(() => _focusedIndex = index);
                                              await _editCurrentLink();
                                            } else {
                                              await _editEntryNote(entry);
                                            }
                                          },
                                          onMoveUp: canMoveUp ? () => _moveEntry(entry, -1) : null,
                                          onMoveDown: canMoveDown ? () => _moveEntry(entry, 1) : null,
                                          onTrash: () => _trashEntry(entry),
                                          onTrashLongPress: widget.tag.startsWith('#') &&
                                              entry.bookNumber > 0 && entry.chapter > 0 && entry.verse > 0
                                              ? () => _trashEntry(entry) : null,
                                          foregroundColor: TagDialogStyles.accent(theme),
                                        ),
                                        const SizedBox(height: 6),
                                        if (entry.userTitle
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true &&
                                            entry.titleFormatJson
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true)
                                          RichText(
                                            textAlign: TextAlign.left,
                                            text: TextSpan(
                                              children:
                                                  buildPresentationTextSpans(
                                                    text: entry.userTitle!
                                                        .trim(),
                                                    baseStyle:
                                                        presentationTextStyle(
                                                          context,
                                                          theme
                                                              .textTheme
                                                              .titleMedium,
                                                          widget.fontScale,
                                                          color: titleColor,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          minFontSize: 16,
                                                          maxFontSize: 26,
                                                        ),
                                                    formatJson:
                                                        entry.titleFormatJson,
                                                  ),
                                            ),
                                          )
                                        else
                                          Text(
                                            _entryTitle(entry, bookName),
                                            style: presentationTextStyle(
                                              context,
                                              theme.textTheme.titleMedium,
                                              widget.fontScale,
                                              color: titleColor,
                                              fontWeight: FontWeight.w800,
                                              minFontSize: 16,
                                              maxFontSize: 26,
                                            ),
                                          ),
                                        const SizedBox(height: 1),
                                        if (_isNoteOnlyEntry(entry) &&
                                            entry.noteFormatJson?.trim().isNotEmpty == true)
                                          RichText(
                                            textAlign: TextAlign.left,
                                            text: TextSpan(
                                              children: buildPresentationTextSpans(
                                                text: _entryNoteText(entry),
                                                baseStyle: presentationTextStyle(
                                                  context,
                                                  theme.textTheme.bodyMedium,
                                                  widget.fontScale,
                                                  color: bodyColor,
                                                  height: 1.25,
                                                  minFontSize: 15,
                                                  maxFontSize: 23,
                                                ),
                                                formatJson: entry.noteFormatJson,
                                              ),
                                            ),
                                          )
                                        else if (entry.displayTextOverride
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true &&
                                            entry.displayTextFormatJson
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true &&
                                            !entry.hasMedia)
                                          RichText(
                                            textAlign: TextAlign.left,
                                            text: TextSpan(
                                              children:
                                                  buildPresentationTextSpans(
                                                    text: entry
                                                        .displayTextOverride!
                                                        .trim(),
                                                    baseStyle:
                                                        presentationTextStyle(
                                                          context,
                                                          theme
                                                              .textTheme
                                                              .bodyMedium,
                                                          widget.fontScale,
                                                          color: bodyColor,
                                                          height: 1.25,
                                                          minFontSize: 15,
                                                          maxFontSize: 23,
                                                        ),
                                                    formatJson: entry
                                                        .displayTextFormatJson,
                                                  ),
                                            ),
                                          )
                                        else
                                          Text(
                                            _entryBody(entry),
                                            style: presentationTextStyle(
                                              context,
                                              theme.textTheme.bodyMedium,
                                              widget.fontScale,
                                              color: bodyColor,
                                              height: 1.25,
                                              minFontSize: 15,
                                              maxFontSize: 23,
                                            ),
                                            softWrap: true,
                                          ),
                                        if (citationText.isNotEmpty &&
                                            _entryTitle(entry, bookName).trim() != citationText.trim() &&
                                            entry.bookNumber > 0) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            citationText,
                                            style: presentationTextStyle(
                                              context,
                                              theme.textTheme.bodySmall,
                                              widget.fontScale,
                                              color: bodyColor.withValues(
                                                alpha: 0.78,
                                              ),
                                              fontWeight: FontWeight.w600,
                                              minFontSize: 12.5,
                                              maxFontSize: 19,
                                            ),
                                          ),
                                        ],
                                        if (!_isDollarRepository) ...[
                                          const SizedBox(height: 8),
                                          _slideLinkControl(entry),
                                        ],
                                        if (hasNote && !_isNoteOnlyEntry(entry)) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: TagDialogStyles.card(
                                                theme,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color:
                                                    TagDialogStyles.outlineColor(
                                                      theme,
                                                    ).withValues(alpha: 0.35),
                                              ),
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.edit_note,
                                                  size: 16,
                                                  color: TagDialogStyles.accent(
                                                    theme,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    _entryNotePreview(entry) ??
                                                        'Note saved',
                                                    style:
                                                        presentationTextStyle(
                                                          context,
                                                          theme
                                                              .textTheme
                                                              .bodySmall,
                                                          widget.fontScale,
                                                          color: bodyColor,
                                                          height: 1.2,
                                                          minFontSize: 12.5,
                                                          maxFontSize: 19,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        if (entry.hasMedia) ...[
                                          const SizedBox(height: 6),
                                          _mediaThumbnails(entry),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MoveTagCategoryDialog extends StatefulWidget {
  const _MoveTagCategoryDialog({
    required this.repository,
    required this.tag,
    required this.currentCategory,
    required this.fontScale,
  });

  final HashTagRepository repository;
  final String tag;
  final String? currentCategory;
  final double fontScale;

  @override
  State<_MoveTagCategoryDialog> createState() => _MoveTagCategoryDialogState();
}

class _MoveTagCategoryResult {
  const _MoveTagCategoryResult({
    required this.targetCategory,
    required this.merged,
    required this.addedCount,
    required this.skippedCount,
    required this.sourceRemoved,
  });

  final String? targetCategory;
  final bool merged;
  final int addedCount;
  final int skippedCount;
  final bool sourceRemoved;
}

class _MoveTagCategoryDialogState extends State<_MoveTagCategoryDialog> {
  List<String> _categoryOptions = const <String>[];
  String _typedCategory = '';
  bool _loading = true;
  String? _errorText;
  bool _fieldEdited = false;
  late final TextEditingController _catController;
  late final FocusNode _catFocusNode;

  @override
  void initState() {
    super.initState();
    _typedCategory = widget.currentCategory?.trim() ?? '';
    _catController = TextEditingController(text: _typedCategory);
    _catFocusNode = FocusNode();
    _loadCategories();
  }

  @override
  void dispose() {
    _catFocusNode.dispose();
    _catController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final options = List<String>.from(
      await widget.repository.loadCategoryOptions(),
    );
    if (!mounted) return;

    final current = widget.currentCategory?.trim() ?? '';
    if (current.isNotEmpty &&
        !options.any((value) => value.toLowerCase() == current.toLowerCase())) {
      options.insert(0, current);
    }

    setState(() {
      _categoryOptions = options;
      _loading = false;
    });

    // Populate RawAutocomplete's internal _options immediately after the
    // widget appears.  RawAutocomplete only calls optionsBuilder on text
    // changes; it starts with an empty _options list, which means tapping
    // the field shows nothing.  Two synchronous value swaps (empty → saved)
    // trigger the listener twice without visible flicker; the second result
    // wins via the _onChangedCallId mechanism, leaving _options = all
    // existing categories so the dropdown opens on first tap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final saved = _catController.value;
      _catController.value = TextEditingValue.empty;
      _catController.value = saved;
    });
  }

  Future<void> _save() async {
    final target = _typedCategory.trim().isEmpty ? null : _typedCategory.trim();
    final current = widget.currentCategory?.trim() ?? '';
    if ((target ?? '').toLowerCase() == current.toLowerCase()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(
      _MoveTagCategoryResult(
        targetCategory: target,
        merged: false,
        addedCount: 0,
        skippedCount: 0,
        sourceRemoved: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = TagDialogStyles.titleTextStyle(
      theme,
      widget.fontScale,
      color: TagDialogStyles.title(theme),
      fontWeight: FontWeight.w900,
    );
    final bodyStyle = TagDialogStyles.bodyTextStyle(
      theme,
      widget.fontScale,
      color: TagDialogStyles.body(theme),
    );

    return AlertDialog(
      title: Text('Change folder', style: titleStyle),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Tag: ${widget.tag}', style: bodyStyle),
                  const SizedBox(height: 4),
                  Text(
                    'Current folder: ${widget.currentCategory?.trim().isNotEmpty == true ? widget.currentCategory!.trim() : 'None'}',
                    style: bodyStyle,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Choose folder',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('None')),
                      for (final category
                          in _categoryOptions
                              .where((c) => c.isNotEmpty)
                              .toSet())
                        DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _catController.text = value;
                        _typedCategory = value;
                        _fieldEdited = true;
                        _errorText = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Autocomplete<String>(
                    textEditingController: _catController,
                    focusNode: _catFocusNode,
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (!_fieldEdited) return _categoryOptions;
                      final text = textEditingValue.text.trim();
                      if (text.isEmpty) return _categoryOptions;
                      return _categoryOptions.where(
                        (opt) => opt.toLowerCase().contains(text.toLowerCase()),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Material(
                          elevation: 4,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Text(option),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                    fieldViewBuilder:
                        (context, textController, focusNode, onFieldSubmitted) {
                          return TextFormField(
                            controller: textController,
                            focusNode: focusNode,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.visiblePassword,
                            textCapitalization: TextCapitalization.none,
                            smartDashesType: SmartDashesType.disabled,
                            smartQuotesType: SmartQuotesType.disabled,
                            decoration: const InputDecoration(
                              labelText: 'Move to folder',
                              hintText: 'Type a name, or clear for None',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _typedCategory = value;
                                _errorText = null;
                                _fieldEdited = true;
                              });
                            },
                          );
                        },
                    onSelected: (String selection) {
                      setState(() {
                        _typedCategory = selection;
                        _errorText = null;
                      });
                    },
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add new folder'),
                      onPressed: _loading ? null : () {
                        setState(() {
                          _typedCategory = '';
                          _fieldEdited = true;
                          _errorText = null;
                          _catController.clear();
                        });
                        _catFocusNode.requestFocus();
                      },
                    ),
                  ),
                  const Text('Enter a new folder name, then choose Move to create it and move this list.'),
                  if (_errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorText!,
                      style: bodyStyle.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: TagDialogStyles.fittedButtonLabel(
            'Cancel',
            style: TagDialogStyles.buttonTextStyle(
              theme,
              widget.fontScale,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: TagDialogStyles.fittedButtonLabel(
            'Move',
            style: TagDialogStyles.buttonTextStyle(
              theme,
              widget.fontScale,
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _RenameTagDialog extends StatefulWidget {
  const _RenameTagDialog({required this.initialTag});

  final String initialTag;

  @override
  State<_RenameTagDialog> createState() => _RenameTagDialogState();
}

class _RenameTagDialogState extends State<_RenameTagDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTag);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename tag'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        textCapitalization: TextCapitalization.none,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        decoration: const InputDecoration(
          labelText: '#tag',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: TagDialogStyles.fittedButtonLabel('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: TagDialogStyles.fittedButtonLabel('Rename'),
        ),
      ],
    );
  }
}

class _ELibraryNoteMetadata {
  const _ELibraryNoteMetadata({
    required this.sourceTitle,
    required this.sourceTitleAcronym,
    required this.sourceLocation,
    required this.sourceReferenceText,
    required this.sourceHref,
    required this.sourceAnchorId,
    required this.sourceSpineIndex,
    required this.sourceParagraphIndex,
    required this.sourceRelativePath,
    required this.sourcePageNumber,
    required this.sourceParagraphNumber,
    required this.searchQuery,
    required this.sourceParagraph,
    required this.excerpt,
    required this.stableRef,
    required this.sourceLibraryItemId,
    required this.selectedTextSnapshot,
    required this.selectionStartBlockIndex,
    required this.selectionStartCharOffset,
    required this.selectionEndBlockIndex,
    required this.selectionEndCharOffset,
    required this.selectionStartTokenIndex,
    required this.selectionEndTokenIndex,
  });

  final String sourceTitle;
  final String sourceTitleAcronym;
  final String sourceLocation;
  final String sourceReferenceText;
  final String sourceHref;
  final String sourceAnchorId;
  final int? sourceSpineIndex;
  final int? sourceParagraphIndex;
  final String sourceRelativePath;
  final int? sourcePageNumber;
  final int? sourceParagraphNumber;
  final String searchQuery;
  final String sourceParagraph;
  final String excerpt;
  final String stableRef;
  final String sourceLibraryItemId;
  final String selectedTextSnapshot;
  final int? selectionStartBlockIndex;
  final int? selectionStartCharOffset;
  final int? selectionEndBlockIndex;
  final int? selectionEndCharOffset;
  final int? selectionStartTokenIndex;
  final int? selectionEndTokenIndex;

  String get citationText {
    final page = sourcePageNumber;
    final paragraph = sourceParagraphNumber;
    if (page != null && paragraph != null && page > 0 && paragraph > 0) {
      return '$page.$paragraph';
    }
    return '';
  }
}

class _HeaderActionChip extends StatelessWidget {
  const _HeaderActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.foregroundColor,
    this.tooltip,
    this.phoneCompact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color foregroundColor;
  final String? tooltip;
  final bool phoneCompact;

  @override
  Widget build(BuildContext context) {
    final labelText = tooltip ?? label;
    if (phoneCompact) {
      return Tooltip(
        message: labelText,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: foregroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(0, 44),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 3),
              Text(label, maxLines: 1, softWrap: false),
            ],
          ),
        ),
      );
    }
    final button = TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: TagDialogStyles.fittedButtonLabel(label),
      style: TextButton.styleFrom(
        foregroundColor: foregroundColor,
        backgroundColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(0, 28),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    return Tooltip(message: labelText, child: button);
  }
}
