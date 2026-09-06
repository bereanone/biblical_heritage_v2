import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/bootstrap/library_root_native.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../utilities/data/pioneer_epub_bulk_import_service.dart';
import '../../utilities/data/pioneer_epub_folder_inventory_service.dart';
import '../../utilities/data/pioneer_zip_extract_service.dart';
import '../../utilities/data/pioneer_archive_org_install_service.dart';
import '../../utilities/presentation/pioneer_text_import_screen.dart';
import '../data/canonical_activation.dart';
import '../data/library_acquisition_batch_runner.dart';
import '../data/library_setup_invitation_service.dart';
import 'add_my_own_epub_screen.dart';
import 'library_acquisition_progress_view.dart';

typedef PioneerFolderPicker =
    Future<({String path, String bookmark})?> Function();
typedef PioneerZipPicker = Future<String?> Function();
typedef PioneerZipExtractor = Future<String> Function(String zipPath);
typedef PioneerFolderSurvey =
    Future<PioneerEpubFolderInventory> Function(
      Directory folder, {
      void Function(int current, int total, String fileName)? onProgress,
    });
typedef PioneerImportPreparer =
    Future<PioneerEpubImportPreparation> Function({
      required PioneerEpubFolderInventory inventory,
      void Function(int current, int total, String title)? onProgress,
      bool Function()? shouldContinue,
    });
typedef PioneerBatchActivator =
    Future<LibraryAcquisitionBatchResult> Function(
      List<LibraryAcquisitionBatchTarget> targets, {
      void Function(LibraryAcquisitionBatchProgress progress)? onProgress,
      bool Function()? shouldContinue,
    });

/// The normal, plain-language Pioneer Library workflow. The existing
/// author/catalog maintenance experience remains available as Advanced Tools.
class ImportPioneerLibraryScreen extends StatefulWidget {
  const ImportPioneerLibraryScreen({
    super.key,
    this.startWithZipPicker = false,
    this.initialZipPath,
    this.pickFolder,
    this.pickZipFile,
    this.extractZip,
    this.surveyFolder,
    this.prepareImport,
    this.activateBatch,
    this.loadSavedFolder,
    this.saveFolder,
    this.advancedToolsBuilder,
  });

  final bool startWithZipPicker;

  /// A zip file path already chosen by the caller (e.g. a plain zip of loose
  /// EPUBs selected via "Check for New Books" that turned out not to be a
  /// .studycollection manifest). When set, this screen skips its own file
  /// picker on open and goes straight to extracting/scanning this file,
  /// landing the user on the normal review/import UI.
  final String? initialZipPath;

  final PioneerFolderPicker? pickFolder;
  final PioneerZipPicker? pickZipFile;
  final PioneerZipExtractor? extractZip;
  final PioneerFolderSurvey? surveyFolder;
  final PioneerImportPreparer? prepareImport;
  final PioneerBatchActivator? activateBatch;
  final Future<String?> Function()? loadSavedFolder;
  final Future<void> Function(String path, String bookmark)? saveFolder;
  final WidgetBuilder? advancedToolsBuilder;

  @override
  State<ImportPioneerLibraryScreen> createState() =>
      _ImportPioneerLibraryScreenState();
}

class _ImportPioneerLibraryScreenState
    extends State<ImportPioneerLibraryScreen> {
  PioneerEpubFolderInventory? _inventory;
  LibraryAcquisitionBatchResult? _result;
  LibraryAcquisitionBatchProgress? _progress;
  bool _loading = true;
  bool _scanning = false;
  bool _running = false;
  bool _cancelled = false;
  int _scanCurrent = 0;
  int _scanTotal = 0;
  String _scanFile = '';
  String? _message;
  int _alreadyUpToDate = 0;
  int _addedOrUpdated = 0;
  int _needsAttention = 0;
  int? _onlineWorkCount;
  PioneerArchiveOrgInstallProgress? _onlineProgress;

  @override
  void initState() {
    super.initState();
    final initialZipPath = widget.initialZipPath;
    if (initialZipPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _importZipFile(initialZipPath);
      });
    } else {
      _loadConfiguredFolder();
      if (widget.startWithZipPicker) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _chooseZipFile();
        });
      }
    }
    PioneerArchiveOrgInstallService.instance
        .inspect()
        .then((value) {
          if (mounted) setState(() => _onlineWorkCount = value);
        })
        .catchError((_) {});
  }

  Future<void> _installOnline() async {
    final count = _onlineWorkCount;
    final countLabel = count == null ? 'the available' : '$count';
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Install Verified Pioneer Books?'),
        content: Text(
          'StudyBible will download $countLabel verified public-domain '
          'Pioneer Authors books individually from the Internet Archive '
          'and install them for offline use. This is not yet the complete '
          '361-work Pioneer catalog. Titles already in your Library are '
          'skipped automatically, and Import Pioneer ZIP remains available '
          'for the remaining works.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _running = true;
      _message = null;
      _progress = const LibraryAcquisitionBatchProgress(
        current: 0,
        total: 0,
        currentTitle: '',
        phase: LibraryAcquisitionPhase.preparing,
      );
    });
    var installed = 0;
    var alreadyInLibrary = 0;
    var needsAttention = 0;
    try {
      final archiveResult = await PioneerArchiveOrgInstallService.instance
          .install(
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _onlineProgress = progress;
                _progress = LibraryAcquisitionBatchProgress(
                  current: progress.current,
                  total: progress.total,
                  currentTitle: progress.title,
                  phase: LibraryAcquisitionPhase.downloading,
                );
              });
            },
          );
      installed += archiveResult.installed;
      alreadyInLibrary += archiveResult.alreadyInLibrary;
      needsAttention += archiveResult.unavailable + archiveResult.failed;
      if (mounted) setState(() => _onlineProgress = null);

      if (!mounted) return;
      setState(() {
        _running = false;
        _onlineProgress = null;
        _progress = null;
        _result = const LibraryAcquisitionBatchResult(
          targets: [],
          outcomes: [],
        );
        _addedOrUpdated = installed;
        _alreadyUpToDate = alreadyInLibrary;
        _needsAttention = needsAttention;
      });
    } on PioneerArchiveOrgInstallCancelled {
      if (mounted) {
        setState(() {
          _running = false;
          _onlineProgress = null;
          _progress = null;
          _message =
              'Installation cancelled. Your existing Library was not changed.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _running = false;
          _onlineProgress = null;
          _progress = null;
          _message =
              'The online installation could not finish. Tap Retry to continue safely.\n$error';
        });
      }
    }
  }

  Future<void> _loadConfiguredFolder() async {
    final path =
        await (widget.loadSavedFolder?.call() ??
            LocalSettingsStore.instance.loadPioneerEpubSourceFolderPath());
    if (!mounted) return;
    if (path == null || path.trim().isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final folder = Directory(path);
    if (widget.surveyFolder == null && !await folder.exists()) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message =
            'The saved Pioneer Library folder is not available. Choose it again to continue.';
      });
      return;
    }
    await _scan(folder);
  }

  Future<void> _chooseFolder() async {
    try {
      final picked =
          await (widget.pickFolder?.call() ?? LibraryRootNative.pickFolder());
      if (picked == null) return;
      final folder = Directory(picked.path);
      if (widget.surveyFolder == null && !await folder.exists()) return;
      if (widget.saveFolder != null) {
        await widget.saveFolder!(picked.path, picked.bookmark);
      } else {
        await LocalSettingsStore.instance.savePioneerEpubSourceFolder(
          path: picked.path,
          bookmark: picked.bookmark,
        );
      }
      await _useFolder(folder);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _scanning = false;
        _message =
            'That folder could not be opened. Choose the Pioneer Library folder and try again.';
      });
    }
  }

  /// Lets the user pick the Pioneer Library ZIP file directly instead of
  /// navigating a folder-tree picker. Selecting a single file is far more
  /// reliable across cloud storage apps (Google Drive's folder picker in
  /// particular tends to just list every file with no clear way to select
  /// the enclosing folder) than the standard SAF folder picker.
  Future<void> _chooseZipFile() async {
    final zipPath =
        await (widget.pickZipFile?.call() ??
            LibraryRootNative.pickPioneerZipFile());
    if (zipPath == null) return;
    await _importZipFile(zipPath);
  }

  Future<void> _importZipFile(String zipPath) async {
    try {
      setState(() {
        _loading = false;
        _scanning = true;
        _message = null;
        _result = null;
        _inventory = null;
      });
      final extractedPath =
          await (widget.extractZip ??
              PioneerZipExtractService.instance.extractToWorkingFolder)(
            zipPath,
          );
      final folder = Directory(extractedPath);
      if (widget.saveFolder != null) {
        await widget.saveFolder!(extractedPath, '');
      } else {
        await LocalSettingsStore.instance.savePioneerEpubSourceFolder(
          path: extractedPath,
          bookmark: '',
        );
      }
      await _useFolder(folder);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _scanning = false;
        _message = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _scanning = false;
        _message =
            'That ZIP file could not be opened. Choose the Pioneer Library '
            'ZIP file and try again.';
      });
    }
  }

  Future<void> _useFolder(Directory folder) async {
    await _scan(folder);
    // A folder/ZIP the user just picked is a clear, deliberate action: go
    // straight to importing instead of making them tap a second button.
    // (A folder loaded automatically from a previously saved location on
    // screen open is not auto-imported — only a fresh, explicit pick is.)
    if (mounted && (_inventory?.validCount ?? 0) > 0) {
      await _importOrUpdate();
    }
  }

  Future<void> _scan(Directory folder) async {
    setState(() {
      _loading = false;
      _scanning = true;
      _message = null;
      _result = null;
      _inventory = null;
      _scanCurrent = 0;
      _scanTotal = 0;
      _scanFile = '';
    });
    try {
      final inventory =
          await (widget.surveyFolder ??
              PioneerEpubFolderInventoryService.instance.survey)(
            folder,
            onProgress: (current, total, fileName) {
              if (!mounted) return;
              setState(() {
                _scanCurrent = current;
                _scanTotal = total;
                _scanFile = fileName;
              });
            },
          );
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _inventory = inventory;
        _alreadyUpToDate = inventory.unchangedCount;
        _needsAttention = inventory.invalidCount;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _message =
            'The Pioneer Library folder could not be checked. No source files were changed.';
      });
    }
  }

  Future<void> _importOrUpdate() async {
    final inventory = _inventory;
    if (inventory == null) return;
    setState(() {
      _running = true;
      _cancelled = false;
      _result = null;
      _progress = const LibraryAcquisitionBatchProgress(
        current: 0,
        total: 0,
        currentTitle: '',
        phase: LibraryAcquisitionPhase.preparing,
      );
      _alreadyUpToDate = inventory.unchangedCount;
      _addedOrUpdated = 0;
      _needsAttention = inventory.invalidCount;
    });

    try {
      final preparation =
          await (widget.prepareImport ??
              PioneerEpubBulkImportService.instance.prepare)(
            inventory: inventory,
            onProgress: (current, total, title) {
              if (!mounted) return;
              setState(() {
                _progress = LibraryAcquisitionBatchProgress(
                  current: current,
                  total: total,
                  currentTitle: title,
                  phase: LibraryAcquisitionPhase.preparing,
                );
              });
            },
            shouldContinue: () => !_cancelled,
          );
      final activated =
          await (widget.activateBatch ??
              LibraryAcquisitionBatchRunner.instance.activate)(
            preparation.targets,
            onProgress: (progress) {
              if (mounted) setState(() => _progress = progress);
            },
            shouldContinue: () => !_cancelled,
          );
      final combined = LibraryAcquisitionBatchResult(
        targets: activated.targets,
        outcomes: <LibraryAcquisitionOutcome>[
          ...preparation.preparationFailures,
          ...activated.outcomes,
        ],
      );
      if (combined.readyCount > 0) {
        await LibrarySetupInvitationService.instance.markCompleted();
      }
      if (!mounted) return;
      setState(() {
        _running = false;
        _progress = null;
        _result = combined;
        _alreadyUpToDate = preparation.skippedUnchangedCount;
        _addedOrUpdated = combined.readyCount;
        _needsAttention =
            preparation.skippedInvalidCount +
            combined.unavailableOutcomes.length;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _progress = null;
        _message =
            'The update could not be completed. Your source files were not changed.';
      });
    }
  }

  void _openAdvancedTools() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            widget.advancedToolsBuilder ??
            (_) => const PioneerTextImportScreen(),
      ),
    );
  }

  void _openSingleBookImport() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AddMyOwnEpubScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pioneer Library')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 700;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 40 : 20,
                vertical: wide ? 36 : 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 880 : 560),
                  child: _buildBody(context, wide),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool wide) {
    if (_loading || _scanning) return _buildChecking(context);
    if (_running) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _onlinePhaseLabel(),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          LibraryAcquisitionProgressView(
            progress: _progress,
            onCancel: () {
              _cancelled = true;
              PioneerArchiveOrgInstallService.instance.cancel();
            },
          ),
          const SizedBox(height: 20),
          _friendlyCounts(),
        ],
      );
    }
    if (_result != null) return _buildCompletion(context);
    if (_inventory != null) return _buildReady(context, wide);
    return _buildFirstTime(context, wide);
  }

  String _onlinePhaseLabel() {
    final progress = _onlineProgress;
    final phase = progress?.phase;
    final label = switch (phase) {
      PioneerArchiveOrgInstallPhase.downloading => 'Downloading…',
      PioneerArchiveOrgInstallPhase.downloaded => 'Downloading…',
      PioneerArchiveOrgInstallPhase.skippedExisting =>
        'Skipping already-installed titles…',
      PioneerArchiveOrgInstallPhase.unavailable => 'Downloading…',
      PioneerArchiveOrgInstallPhase.failed => 'Downloading…',
      PioneerArchiveOrgInstallPhase.activating => 'Updating Library…',
      null => 'Preparing download…',
    };
    if (progress == null || progress.total <= 0) return label;
    return '$label (${progress.current} of ${progress.total})';
  }

  Widget _buildChecking(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Checking Pioneer Library…',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        LinearProgressIndicator(
          value: _scanTotal > 0 ? _scanCurrent / _scanTotal : null,
        ),
        if (_scanFile.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_scanFile, textAlign: TextAlign.center),
        ],
      ],
    );
  }

  Widget _buildFirstTime(BuildContext context, bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.collections_bookmark_outlined,
          size: wide ? 64 : 52,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 18),
        Text(
          'Add your Pioneer Library books.',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Download the verified online portion of the Adventist Pioneer EPUB collection. Import Pioneer ZIP remains available for the works not yet covered by verified online sources.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            key: const Key('pioneer-online-install-action'),
            onPressed: _installOnline,
            icon: const Icon(Icons.download),
            label: const Text('Install Verified Pioneer Books'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            key: const Key('pioneer-zip-action'),
            onPressed: _chooseZipFile,
            icon: const Icon(Icons.folder_zip_outlined),
            label: const Text('Import Pioneer ZIP'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            key: const Key('pioneer-primary-action'),
            onPressed: _chooseFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose an Already-Extracted Folder Instead'),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _openSingleBookImport,
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Add a Book File (EPUB)'),
        ),
        TextButton(
          onPressed: _openAdvancedTools,
          child: const Text('Advanced Tools'),
        ),
      ],
    );
  }

  Widget _buildReady(BuildContext context, bool wide) {
    final inventory = _inventory!;
    final ready = inventory.validCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.library_books_outlined,
          size: wide ? 64 : 52,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          inventory.needsImportCount == 0 && inventory.invalidCount == 0
              ? 'Your Pioneer Library is ready.'
              : '${inventory.totalFound} source books found',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          inventory.invalidCount == 0
              ? '$ready books available'
              : '$ready books are ready\n${inventory.invalidCount} files need attention',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (inventory.skippedNonEpubCount > 0) ...[
          const SizedBox(height: 6),
          Text(
            '${inventory.skippedNonEpubCount} non-book ${inventory.skippedNonEpubCount == 1 ? 'file was' : 'files were'} ignored',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 10),
          Text(_message!, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 26),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            key: const Key('pioneer-online-update-action'),
            onPressed: _installOnline,
            icon: const Icon(Icons.system_update_alt),
            label: const Text('Update Verified Pioneer Books'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 54,
          child: OutlinedButton(
            key: const Key('pioneer-primary-action'),
            onPressed: _importOrUpdate,
            child: const Text('Import / Update Pioneer Library'),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _chooseFolder,
          child: const Text('Change Source Folder'),
        ),
        OutlinedButton.icon(
          onPressed: _openSingleBookImport,
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Add a Book File (EPUB)'),
        ),
        TextButton(
          onPressed: _openAdvancedTools,
          child: const Text('Advanced Tools'),
        ),
      ],
    );
  }

  Widget _buildCompletion(BuildContext context) {
    final checked = _alreadyUpToDate + _addedOrUpdated + _needsAttention;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          _needsAttention == 0
              ? Icons.check_circle_outline
              : Icons.info_outline,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Pioneer Library Updated',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        Text('$checked books checked', textAlign: TextAlign.center),
        Text(
          '$_addedOrUpdated books added or updated',
          textAlign: TextAlign.center,
        ),
        Text(
          '$_alreadyUpToDate already up to date',
          textAlign: TextAlign.center,
        ),
        Text(
          '$_needsAttention ${_needsAttention == 1 ? 'file needs' : 'files need'} attention',
          textAlign: TextAlign.center,
        ),
        if ((_inventory?.skippedNonEpubCount ?? 0) > 0)
          Text(
            '${_inventory!.skippedNonEpubCount} non-book ${_inventory!.skippedNonEpubCount == 1 ? 'file was' : 'files were'} ignored',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => setState(() => _result = null),
          child: const Text('Done'),
        ),
        if (_needsAttention > 0)
          TextButton(
            onPressed: _openAdvancedTools,
            child: const Text('View Details'),
          ),
      ],
    );
  }

  Widget _friendlyCounts() {
    return Column(
      children: [
        Text('Already Up to Date: $_alreadyUpToDate'),
        Text('Added or Updated: $_addedOrUpdated'),
        Text('Needs Attention: $_needsAttention'),
      ],
    );
  }
}
