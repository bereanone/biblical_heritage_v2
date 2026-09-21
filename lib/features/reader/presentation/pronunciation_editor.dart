import 'package:flutter/material.dart';

class PronunciationEditor extends StatefulWidget {
  const PronunciationEditor({
    super.key,
    required this.initial,
    required this.onPreview,
    required this.onSave,
    required this.onStopPreview,
  });
  final Map<String, String> initial;
  final Future<void> Function(String text, Map<String, String> rules) onPreview;
  final Future<void> Function(Map<String, String>) onSave;
  final Future<void> Function() onStopPreview;
  @override
  State<PronunciationEditor> createState() => _PronunciationEditorState();
}

class _PronunciationEditorState extends State<PronunciationEditor> {
  late final Map<String, String> _rules = Map.of(widget.initial);
  final _word = TextEditingController();
  final _spoken = TextEditingController();
  bool _busy = false;
  String? _editing;
  String? _error;

  @override
  void dispose() {
    _word.dispose();
    _spoken.dispose();
    super.dispose();
  }

  Map<String, String> _withDraft() {
    final result = Map<String, String>.of(_rules);
    final word = _word.text.trim();
    if (word.isNotEmpty && _spoken.text.trim().isNotEmpty) {
      result.removeWhere(
        (key, _) => key.toLowerCase() == word.toLowerCase() || key == _editing,
      );
      result[word] = _spoken.text.trim();
    }
    return result;
  }

  void _add() {
    if (_word.text.trim().isEmpty || _spoken.text.trim().isEmpty) {
      setState(() => _error = 'Enter both the word and how to say it.');
      return;
    }
    final updated = _withDraft();
    setState(() {
      _rules
        ..clear()
        ..addAll(updated);
      _editing = null;
      _error = null;
    });
    _word.clear();
    _spoken.clear();
  }

  Future<void> _preview() async {
    if (_word.text.trim().isEmpty || _spoken.text.trim().isEmpty) {
      setState(() => _error = 'Enter a word and how to say it first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onPreview(_word.text.trim(), _withDraft());
    } catch (error) {
      if (mounted) setState(() => _error = 'Preview failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if ((_word.text.trim().isEmpty) != (_spoken.text.trim().isEmpty)) {
      setState(
        () => _error = 'Complete both fields or clear them before saving.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onStopPreview();
      await widget.onSave(_withDraft());
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not save: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pronunciations'),
    content: SizedBox(
      width: 520,
      height: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Change how words are spoken. Book text stays unchanged. Earlier spelling fixes are fallbacks when the dictionary knows the word. New edits take priority.'),
          const SizedBox(height: 12),
          TextField(
            controller: _word,
            decoration: const InputDecoration(
              labelText: 'Word',
              hintText: 'Gomorrah',
            ),
          ),
          TextField(
            controller: _spoken,
            decoration: const InputDecoration(
              labelText: 'Say it as',
              hintText: 'go-morrah',
            ),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: _busy ? null : _preview,
                icon: const Icon(Icons.volume_up),
                label: const Text('Preview'),
              ),
              TextButton(
                onPressed: _busy ? null : _add,
                child: Text(
                  _editing == null ? 'Add correction' : 'Update correction',
                ),
              ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const Divider(),
          Expanded(
            child: ListView(
              children: _rules.entries
                  .map(
                    (entry) => ListTile(
                      title: Text(entry.key),
                      subtitle: Text(entry.value),
                      onTap: _busy
                          ? null
                          : () {
                              setState(() => _editing = entry.key);
                              _word.text = entry.key;
                              _spoken.text = entry.value;
                            },
                      trailing: IconButton(
                        tooltip: 'Remove ${entry.key}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _rules.remove(entry.key);
                                if (_editing == entry.key) {
                                  _editing = null;
                                  _word.clear();
                                  _spoken.clear();
                                }
                              }),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy
            ? null
            : () async {
                await widget.onStopPreview();
                if (context.mounted) Navigator.of(context).pop(false);
              },
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
    ],
  );
}
