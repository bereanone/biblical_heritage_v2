import 'package:flutter/material.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/library_root_native.dart';

class LibraryRootSetupScreen extends StatefulWidget {
  const LibraryRootSetupScreen({super.key});

  @override
  State<LibraryRootSetupScreen> createState() => _LibraryRootSetupScreenState();
}

class _LibraryRootSetupScreenState extends State<LibraryRootSetupScreen> {
  LibraryRootSelection? _selection;
  String? _databasePath;
  String? _tagsPath;
  String? _markupPath;
  String? _graphicsPath;
  String? _mediaPath;
  String? _backupPath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final selection = await LibraryRootService.instance.loadSelection();
    final hasRoot = selection.path != null && selection.exists;
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _loading = false;
    });
    if (!hasRoot) return;
    final results = await Future.wait([
      LibraryRootService.instance.databaseFilePath('user.db'),
      LibraryRootService.instance.tagsPath(),
      LibraryRootService.instance.markupPath(),
      LibraryRootService.instance.graphicsPath(),
      LibraryRootService.instance.mediaPath(),
      LibraryRootService.instance.backupRootPath(),
    ]);
    if (!mounted) return;
    setState(() {
      _databasePath = results[0];
      _tagsPath = results[1];
      _markupPath = results[2];
      _graphicsPath = results[3];
      _mediaPath = results[4];
      _backupPath = results[5];
    });
  }

  Future<void> _setRoot() async {
    final selectedPath = await _pickRootFolder();
    if (!mounted || selectedPath == null || selectedPath.path.trim().isEmpty) {
      return;
    }
    await LibraryRootService.instance.setLibraryRoot(
      path: selectedPath.path,
      bookmark: selectedPath.bookmark,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Library root saved and folders created.')),
    );
    await _load();
  }

  Future<({String path, String bookmark})?> _pickRootFolder() async {
    try {
      return await LibraryRootNative.pickFolder();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Folder picker failed: $error')),
        );
      }
      return null;
    }
  }

  Future<void> _refresh() async {
    final path = _selection?.path;
    if (path == null || path.trim().isEmpty) return;
    await LibraryRootService.instance.ensureStructure(path);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Library folders refreshed.')));
    await _load();
  }

  Widget _pathLine(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SelectableText('$label: ${value ?? "(not set)"}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    return Scaffold(
      appBar: AppBar(title: const Text('Library Root Setup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'This selects the root folder for future user-owned databases, tags, markup, graphics, media, backups, and sync folders.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selection?.path == null
                              ? 'No Library Root selected'
                              : selection!.exists
                              ? 'Library Root selected'
                              : 'Library Root missing, reconnect needed',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _pathLine('Root', selection?.path),
                        _pathLine('Databases/user.db', _databasePath),
                        _pathLine('Tags', _tagsPath),
                        _pathLine('Markup', _markupPath),
                        _pathLine('Graphics', _graphicsPath),
                        _pathLine('Media', _mediaPath),
                        _pathLine('Backups', _backupPath),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton(
                              onPressed: _setRoot,
                              child: const Text('Choose Library Folder'),
                            ),
                            OutlinedButton(
                              onPressed: _refresh,
                              child: const Text('Refresh Folders'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Choose a folder in the native folder picker. The app will create the required subfolders inside it.',
                ),
              ],
            ),
    );
  }
}
