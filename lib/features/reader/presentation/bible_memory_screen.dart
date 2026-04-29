import 'package:flutter/material.dart';

import '../data/bible_memory_repository.dart';
import 'bible_memory_practice_screen.dart';
import 'bible_memory_support.dart';
import 'viewer_reference_picker.dart';

class BibleMemoryScreen extends StatefulWidget {
  const BibleMemoryScreen({super.key});

  @override
  State<BibleMemoryScreen> createState() => _BibleMemoryScreenState();
}

class _BibleMemoryScreenState extends State<BibleMemoryScreen> {
  final BibleMemoryRepository _repository = BibleMemoryRepository();
  bool _loading = true;
  List<MemoryVerse> _items = const <MemoryVerse>[];
  List<String> _groupOptions = const <String>[
    BibleMemorySupport.allGroups,
    BibleMemorySupport.ungrouped,
  ];
  String _selectedGroup = BibleMemorySupport.allGroups;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  List<MemoryVerse> get _visibleItems {
    if (_selectedGroup == BibleMemorySupport.allGroups) return _items;
    if (_selectedGroup == BibleMemorySupport.ungrouped) {
      return _items
          .where((item) => item.groupName == null || item.groupName!.trim().isEmpty)
          .toList();
    }
    return _items
        .where((item) => item.groupName?.trim() == _selectedGroup)
        .toList();
  }

  List<MemoryVerse> get _dueItems {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _visibleItems.where((item) => item.nextDueAt <= now).toList();
  }

  String? get _groupForNewItems {
    if (_selectedGroup == BibleMemorySupport.allGroups ||
        _selectedGroup == BibleMemorySupport.ungrouped) {
      return null;
    }
    return _selectedGroup;
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final items = await _repository.loadAll();
    final tagGroups = await BibleMemorySupport.loadHashTagGroups();
    final memoryGroups = items
        .map((item) => item.groupName?.trim() ?? '')
        .where((group) => group.isNotEmpty)
        .toSet();
    final groups = <String>{...memoryGroups, ...tagGroups}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _items = items;
      _groupOptions = <String>[
        BibleMemorySupport.allGroups,
        BibleMemorySupport.ungrouped,
        ...groups,
      ];
      if (!_groupOptions.contains(_selectedGroup)) {
        _selectedGroup = BibleMemorySupport.allGroups;
      }
      _loading = false;
    });
  }

  Future<void> _openPractice(MemoryVerse verse) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BibleMemoryPracticeScreen(
          memoryVerse: verse,
          repository: _repository,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _addVerse() async {
    final selection = await showViewerReferencePicker(
      context,
      initialBookNumber: 1,
      initialChapter: 1,
      initialVerse: 1,
    );
    if (selection == null || !mounted) return;
    final verseRow = await BibleMemorySupport.loadVerseRow(
      bookNumber: selection.bookNumber,
      chapter: selection.chapter,
      verse: selection.verse,
    );
    if (verseRow == null) {
      _showSnack('Unable to load that verse.');
      return;
    }
    final saved = await _repository.upsertVerse(
      bookNumber: selection.bookNumber,
      bookName: selection.bookName,
      chapter: selection.chapter,
      verse: selection.verse,
      verseText: verseRow['text'] as String,
      groupName: _groupForNewItems,
    );
    await _refresh();
    await _openPractice(saved);
  }

  Future<void> _addRange() async {
    final start = await showViewerReferencePicker(
      context,
      initialBookNumber: 1,
      initialChapter: 1,
      initialVerse: 1,
    );
    if (start == null || !mounted) return;
    _showSnack('Select the last verse in the range...');
    final end = await showViewerReferencePicker(
      context,
      initialBookNumber: start.bookNumber,
      initialChapter: start.chapter,
      initialVerse: start.verse,
    );
    if (end == null || !mounted) return;
    if (start.bookNumber != end.bookNumber) {
      _showSnack('Ranges must stay in the same book for now.');
      return;
    }
    if (_compareRefs(start, end) > 0) {
      _showSnack('Ending reference must be after the start reference.');
      return;
    }
    final rows = await BibleMemorySupport.loadVerseRowsInRange(
      bookNumber: start.bookNumber,
      startChapter: start.chapter,
      startVerse: start.verse,
      endChapter: end.chapter,
      endVerse: end.verse,
    );
    if (rows.isEmpty) {
      _showSnack('Unable to load that verse range.');
      return;
    }
    final bookName = rows.first['book_name']?.toString() ?? start.bookName;
    final verseText = rows
        .map((row) => (row['text']?.toString() ?? '').trim())
        .where((text) => text.isNotEmpty)
        .join(' ');
    if (verseText.isEmpty) {
      _showSnack('That range has no verse text.');
      return;
    }
    final saved = await _repository.upsertPassage(
      bookNumber: start.bookNumber,
      bookName: bookName,
      chapter: start.chapter,
      verse: start.verse,
      endChapter: end.chapter,
      endVerse: end.verse,
      verseText: verseText,
      groupName: _groupForNewItems,
    );
    await _refresh();
    await _openPractice(saved);
  }

  int _compareRefs(ReferenceSelection a, ReferenceSelection b) {
    if (a.bookNumber != b.bookNumber) {
      return a.bookNumber.compareTo(b.bookNumber);
    }
    if (a.chapter != b.chapter) {
      return a.chapter.compareTo(b.chapter);
    }
    return a.verse.compareTo(b.verse);
  }

  Future<void> _importTagGroup() async {
    final result =
        await BibleMemorySupport.importTagGroup(context, _repository);
    if (result == null) {
      _showSnack('No #tag lists found yet.');
      return;
    }
    await _refresh();
    if (!mounted) return;
    if (result.selectedGroup != null) {
      setState(() => _selectedGroup = result.selectedGroup!);
    }
    _showSnack('Imported ${result.importedCount} verses from ${result.selectedGroup}');
  }

  Future<void> _importExternalList() async {
    final result = await BibleMemorySupport.importExternalList(
      context,
      _repository,
      initialGroupName: _groupForNewItems,
    );
    if (result == null) return;
    await _refresh();
    _showSnack('Imported ${result.importedCount} memory entries.');
  }

  Future<void> _exportSelectedGroup() async {
    if (_selectedGroup == BibleMemorySupport.allGroups) {
      _showSnack('Choose a specific group to export.');
      return;
    }
    if (_visibleItems.isEmpty) {
      _showSnack('No verses in this group to export.');
      return;
    }
    await BibleMemorySupport.exportSelectedGroup(
      context,
      selectedGroup: _selectedGroup,
      visibleItems: _visibleItems,
    );
  }

  Future<void> _startDueReview() async {
    final due = _dueItems;
    if (due.isEmpty) return;
    await _openPractice(due.first);
  }

  Future<void> _deleteVerse(MemoryVerse verse) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Memory Verse?'),
        content: Text('Remove ${verse.reference} from memory review?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.deleteVerse(verse.id);
    await _refresh();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleItems = _visibleItems;
    final dueCount = _dueItems.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Bible Memory${_items.isEmpty ? '' : ' · ${_items.length}'}'),
        actions: [
          IconButton(
            tooltip: 'Add Verse',
            onPressed: _addVerse,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Review Queue',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$dueCount due now · ${visibleItems.length} shown (${_items.length} total)',
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.center,
                            child: FilledButton.icon(
                              onPressed: () =>
                                  BibleMemorySupport.showInstructions(context),
                              icon: const Icon(Icons.help_outline),
                              label: const Text('Memory Instructions'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Text(
                                'Group:',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _selectedGroup,
                                  items: _groupOptions
                                      .map(
                                        (group) => DropdownMenuItem<String>(
                                          value: group,
                                          child: Text(group),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() => _selectedGroup = value);
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: _addVerse,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Verse'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _addRange,
                                icon: const Icon(Icons.format_quote),
                                label: const Text('Add Range'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _importTagGroup,
                                icon: const Icon(Icons.tag),
                                label: const Text('Import #Tag Group'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _importExternalList,
                                icon: const Icon(Icons.input),
                                label: const Text('Import External'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _exportSelectedGroup,
                                icon: const Icon(Icons.output),
                                label: const Text('Export Group'),
                              ),
                              OutlinedButton.icon(
                                onPressed: dueCount == 0 ? null : _startDueReview,
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Start Due Review'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Text(
                            'No memory verses yet.\nAdd one to begin.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                        )
                      : visibleItems.isEmpty
                          ? Center(
                              child: Text(
                                'No verses in "$_selectedGroup".',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium,
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                              itemCount: visibleItems.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final item = visibleItems[index];
                                final dueNow = item.nextDueAt <=
                                    DateTime.now().millisecondsSinceEpoch;
                                return Material(
                                  color: dueNow
                                      ? theme.colorScheme.primary.withValues(alpha: 0.12)
                                      : theme.colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(10),
                                  child: ListTile(
                                    onTap: () => _openPractice(item),
                                    onLongPress: () => _deleteVerse(item),
                                    leading: CircleAvatar(
                                      backgroundColor: dueNow
                                          ? theme.colorScheme.primary.withValues(alpha: 0.16)
                                          : theme.colorScheme.surfaceContainerHighest,
                                      child: Text(
                                        item.rangeBadge,
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    ),
                                    title: Text(
                                      item.reference,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${BibleMemorySupport.dueLabel(context, item)} · ${_repository.cadenceLabelForStep(item.reviewStep)}'
                                      '${item.groupName == null || item.groupName!.trim().isEmpty ? '' : ' · ${item.groupName}'}\n'
                                      '${item.verseText}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Drill memory verse',
                                          onPressed: () => _openPractice(item),
                                          icon: const Icon(
                                            Icons.chevron_right,
                                          ),
                                          constraints: const BoxConstraints.tightFor(
                                            width: 40,
                                            height: 40,
                                          ),
                                          padding: const EdgeInsets.all(6),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          tooltip: 'Remove memory verse',
                                          onPressed: () => _deleteVerse(item),
                                          icon: Icon(
                                            Icons.delete,
                                            color: theme.colorScheme.error,
                                          ),
                                          constraints: const BoxConstraints.tightFor(
                                            width: 42,
                                            height: 42,
                                          ),
                                          padding: const EdgeInsets.all(8),
                                          visualDensity: VisualDensity.standard,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }
}
