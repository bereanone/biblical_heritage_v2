import 'package:flutter/material.dart';
import '../data/user_content_removal_service.dart';

class UserContentRemovalScreen extends StatefulWidget {
  const UserContentRemovalScreen({super.key, this.service});
  final UserContentRemovalService? service;
  @override
  State<UserContentRemovalScreen> createState() => _RemovalState();
}

class _RemovalState extends State<UserContentRemovalScreen> {
  late final _service = widget.service ?? UserContentRemovalService();
  var _scope = UserContentRemovalScope.library;
  var _backups = false;
  var _busy = false;
  UserContentRemovalPlan? _plan;
  String? _message;
  String _size(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  Future<void> _preview() async {
    setState(() {
      _busy = true;
      _message = null;
      _plan = null;
    });
    try {
      final plan = await _service.preview(_scope, _backups);
      if (mounted) setState(() => _plan = plan);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final plan = _plan;
    if (plan == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this data permanently?'),
        content: Text(
          plan.allUserData
              ? 'Remove added books, personal tags, notes, highlights, bookmarks, presentations and settings from this app? ${plan.includeBackups ? 'App-library backups will also be removed.' : 'App-library backups will remain.'} The built-in Bible and original files outside the app are kept. This cannot be undone.'
              : 'Remove added library books and their reading copies? Personal tags, notes, highlights and bookmarks are kept. ${plan.includeBackups ? 'App-library backups will also be removed.' : 'App-library backups will remain.'} The built-in Bible and original files outside the app are kept. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove Permanently'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final bytes = await _service.remove(plan);
      if (mounted) {
        setState(() {
          _plan = null;
          _message =
              'Removal finished. Reclaimed ${_size(bytes)}. The built-in Bible is still available. Close and reopen StudyBible2 to refresh all screens.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _plan = null;
          _message =
              'Removal did not finish: $error. Some data may already have been removed. Review another preview and retry; do not assume cleanup is complete.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Remove Added Data')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'The built-in Bible stays in the app.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Downloaded books and imported copies belong in the app’s private library. Android removes that private storage when you uninstall StudyBible2. Original import files and backups you exported elsewhere remain yours.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Older versions also copied files into a shared StudyBible folder. This screen never deletes shared originals. Before removing that old folder with Android Files, review its contents and keep anything used by other apps.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<UserContentRemovalScope>(
            initialValue: _scope,
            decoration: const InputDecoration(labelText: 'What to remove'),
            items: const [
              DropdownMenuItem(
                value: UserContentRemovalScope.library,
                child: Text('Added library books'),
              ),
              DropdownMenuItem(
                value: UserContentRemovalScope.allUserData,
                child: Text('All added data and personal studies'),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _scope = value!;
                    _backups = _scope == UserContentRemovalScope.allUserData;
                    _plan = null;
                  }),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Also remove backups inside the app library'),
            value: _backups,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _backups = value!;
                    _plan = null;
                  }),
          ),
          FilledButton(
            onPressed: _busy ? null : _preview,
            child: const Text('Preview Removal'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Please keep the app open until this finishes.'),
                ],
              ),
            ),
          if (_plan case final plan?) ...[
            const SizedBox(height: 16),
            Text(
              '${plan.files.length} app-owned files: ${_size(plan.fileBytes)}.\nUser and library databases: ${_size(plan.databaseBytes)} before cleanup. The retained records determine how much of this can be reclaimed.',
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _remove,
              child: const Text('Review and Remove'),
            ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(_message!),
            ),
        ],
      ),
    ),
  );
}
