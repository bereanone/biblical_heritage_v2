import 'package:flutter/material.dart';

import '../data/highlight_groups_repository.dart';
import '../data/highlights_repository.dart';
import 'markup_settings_screen.dart';

Future<bool?> showHighlightPopup(
  BuildContext context, {
  required List<String> verseRefs,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _HighlightPopup(verseRefs: verseRefs),
  );
}

class _HighlightPopup extends StatefulWidget {
  const _HighlightPopup({required this.verseRefs});

  final List<String> verseRefs;

  @override
  State<_HighlightPopup> createState() => _HighlightPopupState();
}

class _HighlightPopupState extends State<_HighlightPopup> {
  final HighlightsRepository _repository = HighlightsRepository();

  bool _loading = true;
  List<HighlightGroupRecord> _groups = const <HighlightGroupRecord>[];
  int? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final groups = await _repository.loadGroups();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _selectedGroupId = groups.isEmpty ? null : groups.first.id;
      _loading = false;
    });
  }

  Future<void> _apply() async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;
    await _repository.applyHighlightToVerseRefs(
      groupId: groupId,
      verseRefs: widget.verseRefs,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _remove() async {
    await _repository.removeHighlightsForVerseRefs(widget.verseRefs);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const MarkupSettingsScreen(),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Apply Highlight'),
      content: _loading
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.verseRefs.length == 1
                      ? widget.verseRefs.first
                      : '${widget.verseRefs.first} - ${widget.verseRefs.last}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (_groups.isEmpty) ...[
                  const Text('No highlight groups defined yet.'),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _openSettings,
                    child: const Text('Edit Groups'),
                  ),
                ] else ...[
                  DropdownButtonFormField<int>(
                    initialValue: _selectedGroupId,
                    decoration: const InputDecoration(
                      labelText: 'Highlight Group',
                      border: OutlineInputBorder(),
                    ),
                    items: _groups
                        .map(
                          (group) => DropdownMenuItem<int>(
                            value: group.id,
                            child: Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: group.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(group.name),
                              ],
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) => setState(() => _selectedGroupId = value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _openSettings,
                        child: const Text('Browse Group'),
                      ),
                      TextButton(
                        onPressed: _openSettings,
                        child: const Text('Edit Groups'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
      actions: [
        TextButton(
          onPressed: _groups.isEmpty ? null : _remove,
          child: const Text('Remove'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _groups.isEmpty || _selectedGroupId == null ? null : _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
