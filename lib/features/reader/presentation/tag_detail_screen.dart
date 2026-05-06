import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/study_bible_database.dart';
import '../../../core/theme/app_settings_service.dart';
import 'tag_dialog_styles.dart';
import 'tag_quick_apply_helper.dart';
import 'viewer_presentation_launcher.dart';

class HashTagDetailScreen extends StatefulWidget {
  const HashTagDetailScreen({
    super.key,
    required this.repository,
    required this.tag,
    this.onSelectBlockId,
    this.onSelectTag,
  });

  final HashTagRepository repository;
  final String tag;
  final Future<void> Function(int blockId)? onSelectBlockId;
  final Future<void> Function(String tag)? onSelectTag;

  @override
  State<HashTagDetailScreen> createState() => _HashTagDetailScreenState();
}

class _HashTagDetailScreenState extends State<HashTagDetailScreen> {
  final Map<int, String> _bookNames = <int, String>{};
  bool _loading = true;
  String? _defaultTag;
  List<HashTagEntry> _entries = const <HashTagEntry>[];
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final defaultTag = await widget.repository.loadDefaultTag();
    final entries = await widget.repository.loadEntries(
      widget.tag,
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

  bool get _isDollarRepository => widget.repository is DollarTagRepository;

  bool _isNoteOnlyEntry(HashTagEntry entry) {
    return _isDollarRepository &&
        entry.bookNumber == 0 &&
        (entry.contentHtml?.trim().isNotEmpty == true ||
            entry.verseRef.startsWith('note:'));
  }

  int? _bookNumberForName(String rawBook) {
    final normalized = _normalizeBookKey(rawBook);
    for (final entry in _bookNames.entries) {
      if (_normalizeBookKey(entry.value) == normalized) return entry.key;
    }
    return null;
  }

  int _noteNumberFor(HashTagEntry entry) {
    var count = 0;
    for (final current in _entries) {
      if (!_isNoteOnlyEntry(current)) continue;
      count++;
      if (current.id == entry.id) return count;
    }
    return 1;
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

  Future<void> _makeDefault() async {
    final currentCategory = await widget.repository.loadTagCategory(widget.tag);
    if (currentCategory != null && currentCategory.trim().isNotEmpty) {
      await widget.repository.saveTagCategory(widget.tag, currentCategory);
    }
    await widget.repository.saveDefaultTag(widget.tag);
    await AppSettingsService.instance.saveActiveTagFamily(
      _isDollarRepository ? 'dollar' : 'hash',
    );
    if (!mounted) return;
    setState(() => _defaultTag = widget.tag);
    final onSelectTag = widget.onSelectTag;
    if (onSelectTag != null) {
      await onSelectTag(widget.tag);
    }
    _showSnack('Default set to ${widget.tag}');
  }

  Future<void> _showInstructions() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('How this screen works'),
          content: const Text(
            'Use the up and down arrows on each verse row to change slide order. '
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
      values: {
        'verse_ref': verseRef,
        'book_number': bookNumber,
        'chapter_number': chapter,
        'verse_number': verse,
        'content_html': noteHtml,
      },
    );
    if (!mounted) return;
    await _reload();
    _showSnack('Updated ${_isNoteOnlyEntry(entry) ? 'note' : 'link'}.');
  }

  Future<void> _addNoteSlide() async {
    if (!_isDollarRepository) return;
    final noteController = TextEditingController();
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Note Slide'),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: noteController,
              autofocus: true,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Slide Note',
                border: OutlineInputBorder(),
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
    noteController.dispose();
    if (shouldSave != true) return;
    final clean = _plainTextToHtml(noteController.text);
    if (clean == '<p></p>') {
      _showSnack('Add note content for the slide.');
      return;
    }
    await widget.repository.insertNoteSlide(
      tag: widget.tag,
      contentHtml: clean,
    );
    if (!mounted) return;
    await _reload();
    setState(() {
      _focusedIndex = _entries.isEmpty ? 0 : _entries.length - 1;
    });
    _showSnack('Added note slide to ${widget.tag}.');
  }

  Future<void> _renameTag() async {
    final controller = TextEditingController(text: widget.tag);
    final renamed = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename tag'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '#tag',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: TagDialogStyles.fittedButtonLabel('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: TagDialogStyles.fittedButtonLabel('Rename'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final normalized = widget.repository.normalizeTagName(renamed ?? '');
    if (normalized.isEmpty || normalized == widget.tag) return;
    await widget.repository.renameTag(oldTag: widget.tag, newTag: normalized);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _deleteEntry(HashTagEntry entry) async {
    await widget.repository.deleteEntry(entry.id);
    if (!mounted) return;
    await _reload();
  }

  Future<void> _moveEntry(HashTagEntry entry, int delta) async {
    final changed = await widget.repository.moveEntry(
      tag: widget.tag,
      entryId: entry.id,
      delta: delta,
    );
    if (!mounted || !changed) return;
    await _reload();
  }

  Future<void> _deleteTag() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete entire tag?'),
          content: Text(
            'Delete ${widget.tag} and all ${_entries.length} attached verse(s)? '
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
    await widget.repository.deleteTag(widget.tag);
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
    await showViewerPresentationScreen(
      context,
      entries: _entries,
      initialIndex: _focusedIndex,
    );
  }

  Future<void> _exportToClipboard() async {
    if (_entries.isEmpty) return;
    final lines = <String>[
      '*The following is a formatted sharing list for use in the Biblical Heritage #StudyBible app. Learn more at BiblicalHeritage.net for tutorials, downloads, shared lists, and related links.*',
      '',
      '${widget.tag} (${_entries.length} verse${_entries.length == 1 ? '' : 's'})',
      '',
    ];

    for (final entry in _entries) {
      lines.add(
        '${_bookNames[entry.bookNumber] ?? 'Book ${entry.bookNumber}'} ${entry.chapter}:${entry.verse}',
      );
      final verseText = entry.verseText.trim();
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
    if (_isNoteOnlyEntry(entry)) {
      return 'Note ${_noteNumberFor(entry)}';
    }
    return '$bookName ${entry.chapter}:${entry.verse}';
  }

  String _entryBody(HashTagEntry entry) {
    final noteHtml = entry.contentHtml?.trim() ?? '';
    if (noteHtml.isNotEmpty) {
      final noteText = _cleanStoredHtml(noteHtml);
      if (noteText.isNotEmpty) return noteText;
    }
    final verseText = entry.verseText.trim();
    if (verseText.isNotEmpty) return verseText;
    if (entry.bookNumber == 0 && entry.verseRef.startsWith('note:')) {
      return 'Note slide';
    }
    return entry.verseRef;
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

    final headerDecoration = BoxDecoration(
      color: surfaceHigh,
      border: Border(bottom: BorderSide(color: outlineColor, width: 0.6)),
    );

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
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.tag} · ${_entries.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          height: 1.0,
                          color: titleColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compactHeader = constraints.maxWidth < 700;
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
                                  onPressed: () => Navigator.of(context).pop(),
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
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color: titleColor,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _editCurrentLink,
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Edit Current Link'),
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
                                  visualDensity: VisualDensity.compact,
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
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color: titleColor,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _focusedIndex < _entries.length - 1
                                      ? () => _moveFocusedEntry(1)
                                      : null,
                                  icon: const Icon(Icons.chevron_right),
                                  color: bodyColor,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            if (focusedEntry.bookNumber > 0 &&
                                focusedEntry.verseText.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Current Scripture',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: titleColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                focusedEntry.verseText.trim(),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 14,
                                  color: bodyColor,
                                  height: 1.28,
                                ),
                              ),
                            ],
                            if ((focusedEntry.contentHtml ?? '')
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Study Notes',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: titleColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  _cleanStoredHtml(focusedEntry.contentHtml!),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: bodyColor,
                                    height: 1.28,
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
                              visualDensity: VisualDensity.compact,
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
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: titleColor,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _focusedIndex < _entries.length - 1
                                  ? () => _moveFocusedEntry(1)
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                              color: bodyColor,
                              visualDensity: VisualDensity.compact,
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
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: bodyColor,
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
                            onTap: () {
                              setState(() => _focusedIndex = index);
                              _openVerse(entry);
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
                                      color: outlineColor.withValues(
                                        alpha: 0.35,
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
                                        Text(
                                          _entryTitle(entry, bookName),
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: titleColor,
                                              ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          _entryBody(entry),
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: bodyColor,
                                                height: 1.25,
                                              ),
                                          softWrap: true,
                                        ),
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
                                        tooltip: 'Move up',
                                        onPressed: canMoveUp
                                            ? () => _moveEntry(entry, -1)
                                            : null,
                                        icon: const Icon(
                                          Icons.keyboard_arrow_up,
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
                                      ),
                                      IconButton(
                                        tooltip: 'Delete verse',
                                        onPressed: () => _deleteEntry(entry),
                                        icon: Icon(
                                          Icons.delete,
                                          color: theme.colorScheme.error,
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

class _HeaderActionChip extends StatelessWidget {
  const _HeaderActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.foregroundColor,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color foregroundColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
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
    final labelText = tooltip ?? label;
    return Tooltip(message: labelText, child: button);
  }
}
