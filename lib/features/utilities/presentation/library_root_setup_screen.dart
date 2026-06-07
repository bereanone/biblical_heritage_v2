import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/library_root_native.dart';
import '../data/elibrary_file_management_service.dart';
import '../data/elibrary_root_migration_service.dart';
import '../../reader/data/commentary_research_library_service.dart';

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
  ELibraryStorageSummary? _storageSummary;
  bool _loading = true;
  bool _indexing = false;
  bool _migrating = false;
  bool _showAdvanced = false;
  String? _indexResult;
  String? _migrationResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final selection = await LibraryRootService.instance.loadSelection();
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _loading = false;
    });
    final rootPath = selection.path?.trim() ?? '';
    if (rootPath.isEmpty) {
      if (!mounted) return;
      setState(() {
        _databasePath = null;
        _tagsPath = null;
        _markupPath = null;
        _graphicsPath = null;
        _mediaPath = null;
        _backupPath = null;
        _storageSummary = null;
      });
      return;
    }

    final results = await Future.wait([
      Future<String>.value(p.join(rootPath, 'Databases', 'user.db')),
      Future<String>.value(p.join(rootPath, 'Tags')),
      Future<String>.value(p.join(rootPath, 'Markup')),
      Future<String>.value(p.join(rootPath, 'Graphics')),
      Future<String>.value(p.join(rootPath, 'Media')),
      LibraryRootService.instance.backupRootPath(),
      ELibraryFileManagementService.instance.computeDownloadedStorageSummary(
        rootPath: rootPath,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _databasePath = results[0] as String;
      _tagsPath = results[1] as String;
      _markupPath = results[2] as String;
      _graphicsPath = results[3] as String;
      _mediaPath = results[4] as String;
      _backupPath = results[5] as String;
      _storageSummary = results[6] as ELibraryStorageSummary;
    });
  }

  Future<void> _useThisFolderAsLibraryRoot() async {
    if (_migrating) return;
    final selection = _selection;
    final currentPath = selection?.path?.trim() ?? '';
    if (currentPath.isEmpty) {
      await _useDefaultAppLibraryFolder();
      return;
    }
    final source = selection?.isDefaultAppManaged == true
        ? LibraryRootSource.defaultAppFolder
        : LibraryRootSource.userSelected;
    await _applyLibraryRoot(
      path: currentPath,
      bookmark: selection?.bookmark,
      source: source,
    );
  }

  Future<void> _setRoot() async {
    if (_migrating) return;
    final selectedPath = await _pickRootFolder();
    if (!mounted || selectedPath == null || selectedPath.path.trim().isEmpty) {
      return;
    }
    final defaultAppRoot = await LibraryRootService.instance
        .defaultAppLibraryRootPath();
    final selectedSource = p.normalize(selectedPath.path) ==
            p.normalize(defaultAppRoot)
        ? LibraryRootSource.defaultAppFolder
        : LibraryRootSource.userSelected;
    await _applyLibraryRoot(
      path: selectedPath.path,
      bookmark: selectedPath.bookmark,
      source: selectedSource,
    );
  }

  Future<void> _useDefaultAppLibraryFolder() async {
    if (_migrating) return;
    final defaultPath = await LibraryRootService.instance
        .defaultAppLibraryRootPath();
    if (!mounted) return;
    await _applyLibraryRoot(
      path: defaultPath,
      bookmark: null,
      source: LibraryRootSource.defaultAppFolder,
    );
  }

  Future<void> _resetLibraryRoot() async {
    if (_migrating) return;
    await LibraryRootService.instance.clearLibraryRoot();
    if (!mounted) return;
    setState(() {
      _migrationResult =
          'Saved Library Root setting cleared. This does not delete downloaded books.';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Saved Library Root setting cleared. This does not delete downloaded books.',
        ),
      ),
    );
    await _load();
  }

  Future<void> _retryLoad() async {
    if (_migrating) return;
    await _load();
  }

  void _toggleAdvanced() {
    if (_migrating) return;
    setState(() {
      _showAdvanced = !_showAdvanced;
    });
  }

  Future<void> _applyLibraryRoot({
    required String path,
    required String? bookmark,
    required LibraryRootSource source,
  }) async {
    final selection = await LibraryRootService.instance.loadSelection();
    final currentPath = selection.path?.trim() ?? '';
    final normalizedNewPath = p.normalize(path.trim());
    final normalizedCurrentPath = currentPath.isEmpty
        ? ''
        : p.normalize(currentPath);
    final currentExists = selection.exists;
    final needsMigration = normalizedCurrentPath.isNotEmpty &&
        normalizedCurrentPath != normalizedNewPath &&
        currentExists;

    if (needsMigration) {
      final preview = await ELibraryRootMigrationService.instance.previewMigration(
        sourceRootPath: normalizedCurrentPath,
        destinationRootPath: normalizedNewPath,
      );
      if (preview.totalCount > 0) {
        final confirmed = await _confirmMigration(
          currentSelection: selection,
          destinationPath: normalizedNewPath,
          preview: preview,
        );
        if (confirmed != true) return;

        await _runMigration(
          currentSelection: selection,
          destinationPath: normalizedNewPath,
          bookmark: bookmark,
          source: source,
        );
        return;
      }
    }

    try {
      await LibraryRootService.instance.setLibraryRoot(
        path: normalizedNewPath,
        bookmark: bookmark,
        source: source,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _migrationResult =
            'Could not use that folder as the Library Root: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not use that folder as the Library Root. '
            'Choose Default App Library Folder instead.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _migrationResult = 'Library Root saved and folders created.';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Library root saved and folders created.')),
    );
    await _load();
  }

  Future<bool?> _confirmMigration({
    required LibraryRootSelection currentSelection,
    required String destinationPath,
    required ELibraryRootMigrationPreview preview,
  }) {
    final managedFolders = preview.scannedFolders.isEmpty
        ? 'No managed eLibrary folders were found in the current root.'
        : preview.scannedFolders.join('\n');
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Move existing eLibrary files?'),
          content: SingleChildScrollView(
            child: Text(
              'Current root:\n${currentSelection.path}\n\n'
              'New root:\n$destinationPath\n\n'
              'Found to move: ${preview.epubCount} EPUB '
              '(${_formatBytes(preview.epubSizeBytes)}), '
              '${preview.pdfCount} PDF (${_formatBytes(preview.pdfSizeBytes)}), '
              '${preview.otherManagedCount} other managed files '
              '(${_formatBytes(preview.otherManagedSizeBytes)})\n\n'
              'Managed folders detected:\n$managedFolders\n\n'
              'If this Library Root is shared with another Biblical Heritage or standalone eLibrary app, moving files here may remove files used by that app too. This will not delete tags, notes, highlights, bookmarks, saved presentations, or user.db.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Move Files'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runMigration({
    required LibraryRootSelection currentSelection,
    required String destinationPath,
    required String? bookmark,
    required LibraryRootSource source,
  }) async {
    if (_migrating) return;
    setState(() {
      _migrating = true;
      _migrationResult = 'Migrating existing eLibrary files...';
    });

    try {
      final report = await ELibraryRootMigrationService.instance
          .migrateManagedFiles(
            sourceRootPath: currentSelection.path!,
            destinationRootPath: destinationPath,
          );
      if (!mounted) return;

      final summary = 'Migration complete: moved ${report.movedCount}, '
          'skipped ${report.skippedCount}, conflicts ${report.conflictCount}, '
          'failed ${report.failedCount}.';
      if (report.failedCount > 0) {
        setState(() => _migrationResult = summary);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$summary Source root was left in place.')),
        );
        return;
      }

      await LibraryRootService.instance.setLibraryRoot(
        path: destinationPath,
        bookmark: bookmark,
        source: source,
      );
      if (!mounted) return;
      setState(() => _migrationResult = summary);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$summary Library root updated.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _migrationResult = 'Migration failed: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Migration failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _migrating = false);
      }
    }
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
    if (_migrating) return;
    final path = _selection?.path;
    if (path == null || path.trim().isEmpty) return;
    await LibraryRootService.instance.ensureStructure(path);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Library folders refreshed.')));
    await _load();
  }

  Future<void> _indexBooks() async {
    if (_indexing || _migrating) return;
    final path = _selection?.path;
    if (path == null || path.trim().isEmpty) return;
    setState(() {
      _indexing = true;
      _indexResult = null;
    });
    final result = await CommentaryResearchLibraryService.instance
        .indexLocalCatalogedEpubs();
    if (!mounted) return;
    final total = result.indexed + result.skipped + result.failed;
    setState(() {
      _indexing = false;
      _indexResult = total == 0
          ? 'Library is already indexed'
          : 'Indexing complete — ${result.indexed} indexed, '
              '${result.skipped} skipped, ${result.failed} failed';
    });
  }

  Widget _pathLine(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SelectableText('$label: ${value ?? "(not set)"}'),
    );
  }

  Widget _setupLeading(BuildContext context) {
    final inset = defaultTargetPlatform == TargetPlatform.macOS ? 48.0 : 0.0;
    return Padding(
      padding: EdgeInsets.only(left: inset),
      child: const BackButton(),
    );
  }

  double _setupLeadingWidth() {
    return 56 + (defaultTargetPlatform == TargetPlatform.macOS ? 48.0 : 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final needsReconnect = selection?.path != null && selection?.exists == false;
    final rootMessage = needsReconnect
        ? 'Library Root needs reconnecting.\nYour downloaded books have not been deleted. Reconnect or reselect your Library Root to use eLibrary.'
        : selection?.statusLabel ?? 'No Library Root selected.';
    final primaryRootActionLabel = needsReconnect
        ? 'Reconnect Library Root'
        : 'Use this folder as Library Root';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library Root Setup'),
        leading: _setupLeading(context),
        leadingWidth: _setupLeadingWidth(),
        titleSpacing: 0,
      ),
      body: SafeArea(
        top: false,
        child: _loading
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
                          rootMessage,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _pathLine('Status badge', selection?.badgeLabel),
                        _pathLine('Root path', selection?.path),
                        _pathLine('Root source', selection?.sourceLabel),
                        _pathLine('Databases/user.db', _databasePath),
                        _pathLine('Tags', _tagsPath),
                        _pathLine('Markup', _markupPath),
                        _pathLine('Graphics', _graphicsPath),
                        _pathLine('Media', _mediaPath),
                        _pathLine('Backups', _backupPath),
                        _pathLine(
                          'Downloaded EPUBs',
                          _storageSummary == null
                              ? null
                              : '${_storageSummary!.epubCount}',
                        ),
                        _pathLine(
                          'Downloaded PDFs',
                          _storageSummary == null
                              ? null
                              : '${_storageSummary!.pdfCount}',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton(
                              onPressed: _migrating
                                  ? null
                                  : _useThisFolderAsLibraryRoot,
                              child: Text(primaryRootActionLabel),
                            ),
                            FilledButton.tonal(
                              onPressed: _migrating ? null : _setRoot,
                              child: const Text(
                                'Choose Different Folder',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _migrating ? null : _useDefaultAppLibraryFolder,
                              child: const Text('Use Default App Library Folder'),
                            ),
                            OutlinedButton(
                              onPressed: _migrating ? null : _retryLoad,
                              child: const Text('Retry'),
                            ),
                            TextButton(
                              onPressed: _toggleAdvanced,
                              child: Text(
                                _showAdvanced
                                    ? 'Hide Advanced Diagnostics'
                                    : 'Advanced Diagnostics',
                              ),
                            ),
                          ],
                        ),
                        if (_showAdvanced) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Advanced actions are for troubleshooting only. They do not delete downloaded books unless a user chooses a move operation.',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              OutlinedButton(
                                onPressed: _migrating ? null : _resetLibraryRoot,
                                child: const Text(
                                  'Clear saved Library Root setting',
                                ),
                              ),
                              OutlinedButton(
                                onPressed: (_selection?.path?.isNotEmpty == true) &&
                                        !_indexing &&
                                        !_migrating
                                    ? _indexBooks
                                    : null,
                                child: Text(
                                  _indexing
                                      ? 'Indexing eLibrary books...'
                                      : 'Index New/Changed Books',
                                ),
                              ),
                              OutlinedButton(
                                onPressed: _migrating ? null : _refresh,
                                child: const Text('Refresh Folders'),
                              ),
                            ],
                          ),
                        ],
                        if (_indexResult != null) ...[
                          const SizedBox(height: 8),
                          Text(_indexResult!),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Choose a folder in the native folder picker, or use the default app-managed folder. The app will create the required subfolders inside the selected Library Root.',
                ),
                if (_migrationResult != null) ...[
                  const SizedBox(height: 12),
                  Text(_migrationResult!),
                ],
                ],
              ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = -1;
    do {
      value /= 1024;
      unitIndex += 1;
    } while (value >= 1024 && unitIndex < units.length - 1);
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unitIndex]}';
  }
}
