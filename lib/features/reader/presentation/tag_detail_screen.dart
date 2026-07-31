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
import '../data/presentation/presentation_models.dart';
import '../data/presentation/presentation_text_format.dart';
import 'presentation_prep/presentation_ui_helpers.dart';
import 'tag_dialog_styles.dart';
import 'tag_quick_apply_helper.dart';
import 'viewer_presentation_launcher.dart';

part 'tag_detail_screen_dialogs.dart';

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
    _showSnack(
      currentCategory == null || currentCategory.trim().isEmpty
          ? 'Default set to ${widget.tag}'
          : 'Default set to ${widget.tag} in $currentCategory',
    );
  }

  Future<void> _showInstructions() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('How this screen works'),
          content: const Text(
            'Use the up and down arrows on each verse row to change slide order. '
            'Tap the slide label to group rows onto the same presentation slide. '
            'Tap the presentation button to open presentation mode, or a verse row to open that verse in the reader. '
            'Use Make default to set the starting tag, Rename to change the tag name, and Erase to delete it.',
          ),
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
    _showSnack('Updated ${_isNoteOnlyEntry(entry) ? 'note' : 'link'}.');
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
    _showSnack('Added note slide to ${widget.tag}.');
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
      _showSnack('No category change.');
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
        _showSnack(
          'Merged copy only: ${chosenCategory.addedCount} added to '
          '${widget.tag} · $targetLabel, ${chosenCategory.skippedCount} '
          'skipped as duplicates. Source tag was left unchanged.',
        );
      } else {
        _showSnack(
          'No new cards added. All source cards already exist in '
          '${widget.tag} · $targetLabel. Source tag was left unchanged.',
        );
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
    _showSnack('Moved ${widget.tag} from $sourceLabel to $targetLabel');
  }

  Future<void> _deleteEntry(HashTagEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Move to Trash?'),
          content: const Text(
            'Move this card to Trash? You can restore it later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: TagDialogStyles.fittedButtonLabel('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: TagDialogStyles.fittedButtonLabel('Move to Trash'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await widget.repository.deleteEntry(
      entry.id,
      normalized: entry.isNormalized,
    );
    if (!mounted) return;
    _markChanged();
    await _notifyParentChanged();
    await _reload();
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
    final lines = <String>[
      '*The following is a formatted sharing list for use in the Biblical Heritage #StudyBible app. Learn more at BiblicalHeritage.net for tutorials, downloads, shared lists, and related links.*',
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
          lines.addAll(noteText.split('\n'));
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
          : entry.verseText.trim();
      if (verseText.isNotEmpty) {
        lines.add(verseText);
      } else {
        final fallback = await StudyBibleDatabase.instance.loadVerseText(
          bookNumber: entry.bookNumber,
          chapter: entry.chapter,
          verse: entry.verse,
        );
        final resolvedText = fallback?.trim() ?? '';
        if (resolvedText.isNotEmpty) {
          lines.add(resolvedText);
        }
      }
      final noteText = _entryNoteText(entry).trim();
      if (noteText.isNotEmpty) {
        lines.add('Note: ${noteText.replaceAll('\n', ' ')}');
      }
      lines.add('');
    }

    await Clipboard.setData(ClipboardData(text: lines.join('\n').trimRight()));
    if (!mounted) return;
    _showSnack('Copied to clipboard.');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
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
    final verseText = entry.verseText.trim();
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

  String _slideAssignmentLabel(HashTagEntry entry) {
    final slideNumber = entry.presentationSlideNumber;
    final placement = entry.presentationSlideRegion;
    final regionLabel =
        placement == null || placement == PresentationItemPlacement.auto
        ? ''
        : ' · ${presentationItemPlacementLabel(placement)}';
    if (slideNumber == null || slideNumber <= 0) {
      return 'Auto slide$regionLabel';
    }
    return 'Slide $slideNumber$regionLabel';
  }

  Future<void> _editSlideAssignment(HashTagEntry entry) async {
    if (_isDollarRepository) return;
    final controller = TextEditingController(
      text: entry.presentationSlideNumber?.toString() ?? '',
    );
    var selectedPlacement =
        entry.presentationSlideRegion ?? PresentationItemPlacement.auto;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Slide assignment'),
          content: SizedBox(
            width: 420,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Slide number',
                        hintText: 'Leave blank for automatic',
                        helperText: 'Blank or 0 clears the slide number.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<PresentationItemPlacement>(
                      initialValue: selectedPlacement,
                      decoration: const InputDecoration(
                        labelText: 'Slide region',
                        helperText: 'Use Auto unless you need a fixed region.',
                        border: OutlineInputBorder(),
                      ),
                      items: presentationItemPlacementOptions
                          .map(
                            (placement) =>
                                DropdownMenuItem<PresentationItemPlacement>(
                                  value: placement,
                                  child: Text(
                                    presentationItemPlacementLabel(placement),
                                  ),
                                ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedPlacement = value;
                        });
                      },
                    ),
                  ],
                );
              },
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
    final rawValue = controller.text.trim();
    controller.dispose();
    if (shouldSave != true) return;

    int? slideNumber;
    if (rawValue.isNotEmpty) {
      final parsed = int.tryParse(rawValue);
      if (parsed == null) {
        _showSnack('Enter a whole slide number.');
        return;
      }
      slideNumber = parsed > 0 ? parsed : null;
    }

    await widget.repository.updateEntry(
      id: entry.id,
      normalized: entry.isNormalized,
      values: {
        'presentation_slide_number': slideNumber,
        'presentation_slide_region':
            slideNumber == null ||
                selectedPlacement == PresentationItemPlacement.auto
            ? null
            : presentationItemPlacementToJson(selectedPlacement),
      },
    );
    if (!mounted) return;
    _markChanged();
    await _notifyParentChanged();
    await _reload();
    _showSnack(
      slideNumber == null
          ? 'Cleared slide assignment.'
          : 'Assigned to slide $slideNumber.',
    );
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
    _showSnack(
      'Note saved for ${_isNoteOnlyEntry(entry) ? 'content item' : _entryTitle(entry, _bookNames[entry.bookNumber] ?? 'Book ${entry.bookNumber}')}.',
    );
  }

  Future<void> _addContentItem() async {
    if (_isDollarRepository) return;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _ContentItemDialog(
          repository: widget.repository,
          tag: widget.tag,
          fontScale: widget.fontScale,
        );
      },
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
    _showSnack('Added note item to ${widget.tag}.');
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
                final compactHeader = constraints.maxWidth < 700;
                final displayTag = _resolvedCategory != null
                    ? '${widget.tag} · ${_resolvedCategory!}'
                    : widget.tag;
                Widget buildTitle({bool includeCount = true}) => Text(
                  includeCount
                      ? '$displayTag · ${_entries.length}'
                      : displayTag,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: presentationTextStyle(
                    context,
                    theme.textTheme.titleLarge,
                    widget.fontScale,
                    fontSize: 18,
                    color: titleColor,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    height: 1.0,
                    minFontSize: 18,
                    maxFontSize: 26,
                  ),
                );
                if (compactHeader) {
                  const phoneActionSize = 44.0;
                  Widget phoneAction({
                    required IconData icon,
                    required String label,
                    required String tooltip,
                    required VoidCallback? onPressed,
                    Color? foregroundColor,
                  }) => SizedBox(
                    height: phoneActionSize,
                    child: _HeaderActionChip(
                      icon: icon,
                      label: label,
                      tooltip: tooltip,
                      onPressed: onPressed,
                      foregroundColor:
                          foregroundColor ?? headerButtonForeground,
                      phoneCompact: true,
                    ),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: buildTitle(includeCount: false)),
                          Text(
                            '· ${_entries.length}',
                            key: const ValueKey('phone-tag-item-count'),
                            style: presentationTextStyle(
                              context,
                              theme.textTheme.titleLarge,
                              widget.fontScale,
                              fontSize: 18,
                              color: titleColor,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                              height: 1.0,
                              minFontSize: 18,
                              maxFontSize: 26,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: _closeDetail,
                            icon: const Icon(Icons.close),
                            color: titleColor,
                            constraints: const BoxConstraints.tightFor(
                              width: phoneActionSize,
                              height: phoneActionSize,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        key: const ValueKey('phone-tag-toolbar-wrap'),
                        children: [
                          Wrap(
                            spacing: 4,
                            children: [
                              phoneAction(
                                icon: defaultActive
                                    ? Icons.check_circle
                                    : Icons.check_circle_outline,
                                label: 'Default',
                                tooltip: defaultActive
                                    ? 'Current default tag'
                                    : 'Set as default tag',
                                onPressed: _makeDefault,
                              ),
                              phoneAction(
                                icon: Icons.help_outline,
                                label: 'Info',
                                tooltip: 'Show instructions',
                                onPressed: _showInstructions,
                              ),
                              phoneAction(
                                icon: Icons.note_add_outlined,
                                label: 'Add',
                                tooltip: _isDollarRepository
                                    ? 'Add Note Slide'
                                    : 'Add Content Item',
                                onPressed: _isDollarRepository
                                    ? _addNoteSlide
                                    : _addContentItem,
                              ),
                              phoneAction(
                                icon: Icons.slideshow_rounded,
                                label: 'Presentation',
                                tooltip: 'Presentation Mode',
                                onPressed: focusedEntry == null
                                    ? null
                                    : _openPresentationMode,
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 4,
                            children: [
                              phoneAction(
                                icon: Icons.arrow_upward_rounded,
                                label: 'Export',
                                tooltip: 'Export to clipboard',
                                onPressed: _entries.isEmpty
                                    ? null
                                    : _exportToClipboard,
                              ),
                              phoneAction(
                                icon: Icons.edit_outlined,
                                label: 'Rename',
                                tooltip: 'Rename',
                                onPressed: _renameTag,
                              ),
                              phoneAction(
                                icon: Icons.drive_file_move_outline,
                                label: 'Move',
                                tooltip: 'Move to category',
                                onPressed: _changeCategory,
                              ),
                              phoneAction(
                                icon: Icons.delete_forever,
                                label: 'Delete',
                                tooltip: 'Delete entire tag',
                                onPressed: _deleteTag,
                                foregroundColor: theme.colorScheme.error,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$displayTag · ${_entries.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: presentationTextStyle(
                          context,
                          theme.textTheme.titleLarge,
                          widget.fontScale,
                          fontSize: 18,
                          color: titleColor,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          height: 1.0,
                          minFontSize: 18,
                          maxFontSize: 26,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _HeaderActionChip(
                                  icon: defaultActive
                                      ? Icons.check_circle
                                      : Icons.check_circle_outline,
                                  label: defaultActive
                                      ? 'Default'
                                      : (compactHeader
                                            ? 'Set default'
                                            : 'Make default'),
                                  tooltip: defaultActive
                                      ? 'Current default tag'
                                      : 'Set as default tag',
                                  onPressed: _makeDefault,
                                  foregroundColor: headerButtonForeground,
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: 'Show instructions',
                                  onPressed: _showInstructions,
                                  icon: const Icon(Icons.help_outline),
                                  color: headerButtonForeground,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                    height: 36,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                if (!_isDollarRepository) ...[
                                  IconButton(
                                    tooltip: 'Add Content Item',
                                    onPressed: _addContentItem,
                                    icon: const Icon(Icons.note_add_outlined),
                                    color: headerButtonForeground,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 36,
                                      height: 36,
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 2),
                                ],
                                if (_isDollarRepository) ...[
                                  IconButton(
                                    tooltip: 'Add Note Slide',
                                    onPressed: _addNoteSlide,
                                    icon: const Icon(Icons.note_add_outlined),
                                    color: headerButtonForeground,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 36,
                                      height: 36,
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 2),
                                ],
                                IconButton(
                                  tooltip: 'Presentation Mode',
                                  onPressed: focusedEntry == null
                                      ? null
                                      : _openPresentationMode,
                                  icon: const Icon(Icons.slideshow_rounded),
                                  color: headerButtonForeground,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                    height: 36,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  tooltip: 'Export to clipboard',
                                  onPressed: _entries.isEmpty
                                      ? null
                                      : _exportToClipboard,
                                  icon: const Icon(Icons.arrow_upward_rounded),
                                  color: headerButtonForeground,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                    height: 36,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  tooltip: 'Rename',
                                  onPressed: _renameTag,
                                  icon: const Icon(Icons.edit_outlined),
                                  color: headerButtonForeground,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                    height: 36,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 2),
                                _HeaderActionChip(
                                  icon: Icons.drive_file_move_outline,
                                  label: 'Move',
                                  tooltip: 'Move to category',
                                  onPressed: _changeCategory,
                                  foregroundColor: headerButtonForeground,
                                ),
                                const SizedBox(width: 2),
                                IconButton(
                                  tooltip: 'Delete entire tag',
                                  onPressed: _deleteTag,
                                  icon: const Icon(Icons.delete_forever),
                                  color: theme.colorScheme.error,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                    height: 36,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  tooltip: 'Close',
                                  onPressed: _closeDetail,
                                  icon: const Icon(Icons.close),
                                  color: titleColor,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                    height: 36,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
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
                                focusedEntry.verseText.trim(),
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
                                        if (entry.displayTextOverride
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
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton.icon(
                                              onPressed: () =>
                                                  _editSlideAssignment(entry),
                                              icon: const Icon(
                                                Icons.slideshow_rounded,
                                                size: 16,
                                              ),
                                              label: Text(
                                                _slideAssignmentLabel(entry),
                                                style: presentationTextStyle(
                                                  context,
                                                  theme.textTheme.labelLarge,
                                                  widget.fontScale,
                                                  fontWeight: FontWeight.w700,
                                                  minFontSize: 12.5,
                                                  maxFontSize: 20,
                                                ),
                                              ),
                                              style: TextButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                minimumSize: const Size(0, 36),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (_isNoteOnlyEntry(entry))
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: Text(
                                              'Note-only item',
                                              style: presentationTextStyle(
                                                context,
                                                theme.textTheme.bodySmall,
                                                widget.fontScale,
                                                color: bodyColor,
                                                minFontSize: 12.5,
                                                maxFontSize: 19,
                                              ),
                                            ),
                                          ),
                                        if (hasNote) ...[
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
                                                  Icons.image_outlined,
                                                  size: 16,
                                                  color: TagDialogStyles.accent(
                                                    theme,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    entry.mediaRefs.length == 1
                                                        ? '1 image attached'
                                                        : '${entry.mediaRefs.length} images attached',
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
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Wrap(
                                    spacing: 2,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      IconButton(
                                        tooltip: _isDollarRepository
                                            ? 'Edit item'
                                            : 'Edit item',
                                        onPressed: () async {
                                          if (_isDollarRepository) {
                                            setState(
                                              () => _focusedIndex = index,
                                            );
                                            await _editCurrentLink();
                                          } else {
                                            await _editEntryNote(entry);
                                          }
                                        },
                                        icon: Icon(
                                          Icons.edit_outlined,
                                          color: TagDialogStyles.accent(theme),
                                        ),
                                        iconSize: presentationScaledSize(
                                          context,
                                          22,
                                          widget.fontScale,
                                          min: 20,
                                          max: 26,
                                        ),
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 44,
                                              height: 44,
                                            ),
                                      ),
                                      IconButton(
                                        tooltip: 'Move up',
                                        onPressed: canMoveUp
                                            ? () => _moveEntry(entry, -1)
                                            : null,
                                        icon: const Icon(
                                          Icons.keyboard_arrow_up,
                                        ),
                                        iconSize: presentationScaledSize(
                                          context,
                                          22,
                                          widget.fontScale,
                                          min: 20,
                                          max: 26,
                                        ),
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 44,
                                              height: 44,
                                            ),
                                      ),
                                      IconButton(
                                        tooltip: 'Move down',
                                        onPressed: canMoveDown
                                            ? () => _moveEntry(entry, 1)
                                            : null,
                                        icon: const Icon(
                                          Icons.keyboard_arrow_down,
                                        ),
                                        iconSize: presentationScaledSize(
                                          context,
                                          22,
                                          widget.fontScale,
                                          min: 20,
                                          max: 26,
                                        ),
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 44,
                                              height: 44,
                                            ),
                                      ),
                                      IconButton(
                                        tooltip: 'Move to Trash',
                                        onPressed: () => _deleteEntry(entry),
                                        icon: Icon(
                                          Icons.delete,
                                          color: theme.colorScheme.error,
                                        ),
                                        iconSize: presentationScaledSize(
                                          context,
                                          22,
                                          widget.fontScale,
                                          min: 20,
                                          max: 26,
                                        ),
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 44,
                                              height: 44,
                                            ),
                                      ),
                                    ],
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
      title: Text('Change category', style: titleStyle),
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
                    'Current category: ${widget.currentCategory?.trim().isNotEmpty == true ? widget.currentCategory!.trim() : 'None'}',
                    style: bodyStyle,
                  ),
                  const SizedBox(height: 14),
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
                              labelText: 'Move to category',
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
