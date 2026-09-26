import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/canonical_activation.dart';
import '../data/library_acquisition_batch_runner.dart';
import '../data/library_acquisition_orchestrator.dart';
import '../data/library_catalog_service.dart';
import '../data/library_setup_invitation_service.dart';
import '../data/user_epub_import_service.dart';
import 'library_acquisition_progress_view.dart';
import 'library_book_reader_screen.dart';

/// "Add My Own EPUB" — pick one EPUB, validate, prepare, ready to read.
/// The reader is never opened to trigger canonical preparation; this
/// screen calls [LibraryAcquisitionOrchestrator.prepareExistingEpub]
/// directly after the file is copied into the library.
class AddMyOwnEpubScreen extends StatefulWidget {
  const AddMyOwnEpubScreen({super.key});

  @override
  State<AddMyOwnEpubScreen> createState() => _AddMyOwnEpubScreenState();
}

class _AddMyOwnEpubScreenState extends State<AddMyOwnEpubScreen> {
  bool _running = false;
  LibraryAcquisitionBatchProgress? _progress;
  LibraryAcquisitionBatchResult? _result;
  UserEpubImportResult? _imported;

  Future<void> _pickAndImport() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose an EPUB',
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const <String>['epub'],
    );
    final path = picked?.files.single.path?.trim() ?? '';
    if (path.isEmpty) return;

    UserEpubInspection inspection;
    try {
      inspection = await UserEpubImportService.instance.inspect(path);
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('This EPUB is not supported'),
          content: const Text(
            'StudyBible could not find a complete EPUB with readable pages. '
            'The selected file was not copied or changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Choose Another File'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm this book'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              inspection.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (inspection.creator != null) ...[
              const SizedBox(height: 6),
              Text(inspection.creator!),
            ],
            const SizedBox(height: 12),
            Text('${inspection.spineItemCount} reading section(s)'),
            const SizedBox(height: 8),
            const Text(
              'StudyBible will keep this exact edition separate from other '
              'books with a similar title.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import Book'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _running = true;
      _imported = null;
      _result = null;
      _progress = LibraryAcquisitionBatchProgress(
        current: 0,
        total: 1,
        currentTitle: inspection.title,
        phase: LibraryAcquisitionPhase.validating,
      );
    });

    LibraryAcquisitionOutcome outcome;
    try {
      final imported = await UserEpubImportService.instance.copyIntoLibrary(
        path,
        confirmedInspection: inspection,
      );
      _imported = imported;
      if (mounted) {
        setState(() {
          _progress = LibraryAcquisitionBatchProgress(
            current: 0,
            total: 1,
            currentTitle: imported.title,
            phase: LibraryAcquisitionPhase.preparing,
          );
        });
      }
      outcome = await LibraryAcquisitionOrchestrator.instance
          .prepareExistingEpub(
            libraryItemId: imported.libraryItemId,
            relativePath: imported.relativePath,
          );
    } catch (error) {
      outcome = LibraryAcquisitionOutcome(
        libraryItemId: '',
        phase: LibraryAcquisitionPhase.failedValidation,
        userSummary: 'The selected book is not a readable EPUB.',
        technicalDetail: error.toString(),
        retryable: false,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: false,
      );
    }
    if (!mounted) return;
    if (outcome.isReady) {
      await LibrarySetupInvitationService.instance.markCompleted();
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _progress = null;
      _result = LibraryAcquisitionBatchResult(
        targets: const <LibraryAcquisitionBatchTarget>[],
        outcomes: <LibraryAcquisitionOutcome>[outcome],
      );
    });
  }

  Future<void> _retry() async {
    final imported = _imported;
    if (_running || imported == null) return;
    setState(() {
      _running = true;
      _result = null;
      _progress = LibraryAcquisitionBatchProgress(
        current: 0,
        total: 1,
        currentTitle: imported.title,
        phase: LibraryAcquisitionPhase.preparing,
      );
    });
    LibraryAcquisitionOutcome outcome;
    try {
      outcome = await LibraryAcquisitionOrchestrator.instance
          .prepareExistingEpub(
            libraryItemId: imported.libraryItemId,
            relativePath: imported.relativePath,
          );
    } catch (error) {
      outcome = LibraryAcquisitionOutcome(
        libraryItemId: imported.libraryItemId,
        phase: LibraryAcquisitionPhase.failedImport,
        userSummary: 'This book still needs attention before it is ready.',
        technicalDetail: error.toString(),
        retryable: true,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: true,
      );
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _progress = null;
      _result = LibraryAcquisitionBatchResult(
        targets: <LibraryAcquisitionBatchTarget>[
          LibraryAcquisitionBatchTarget(
            libraryItemId: imported.libraryItemId,
            relativePath: imported.relativePath,
            title: imported.title,
          ),
        ],
        outcomes: <LibraryAcquisitionOutcome>[outcome],
      );
    });
  }

  Future<void> _openReadyBook() async {
    final imported = _imported;
    if (imported == null) return;
    final item = await LibraryCatalogService.instance.loadItemById(
      imported.libraryItemId,
    );
    if (!mounted || item == null) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryBookReaderScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Import Book')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _running || result != null
                  ? LibraryAcquisitionProgressView(
                      progress: _progress,
                      result: result,
                      onRetryFailed:
                          !_running &&
                              result?.unavailableOutcomes.isNotEmpty == true
                          ? _retry
                          : null,
                      onOpenReady: !_running && result?.readyCount == 1
                          ? _openReadyBook
                          : null,
                      onDone: _running
                          ? null
                          : () => Navigator.of(context).pop(),
                      doneLabel: result?.readyCount == 1
                          ? 'Back to Library'
                          : 'Done',
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Choose a supported EPUB file from this device. '
                          'StudyBible keeps the original file, checks the '
                          'book, and prepares its Contents and search '
                          'automatically. PDF reading is not available yet.',
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _pickAndImport,
                          child: const Text('Choose EPUB'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
