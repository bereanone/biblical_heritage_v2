import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/canonical_activation.dart';
import '../data/library_acquisition_batch_runner.dart';
import '../data/library_acquisition_orchestrator.dart';
import '../data/library_setup_invitation_service.dart';
import '../data/user_epub_import_service.dart';
import 'library_acquisition_progress_view.dart';

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
  LibraryAcquisitionBatchResult? _result;

  Future<void> _pickAndImport() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose an EPUB',
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const <String>['epub'],
    );
    final path = picked?.files.single.path?.trim() ?? '';
    if (path.isEmpty) return;

    setState(() {
      _running = true;
      _result = null;
    });

    LibraryAcquisitionOutcome outcome;
    try {
      final imported = await UserEpubImportService.instance.copyIntoLibrary(
        path,
      );
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
      _result = LibraryAcquisitionBatchResult(
        targets: const <LibraryAcquisitionBatchTarget>[],
        outcomes: <LibraryAcquisitionOutcome>[outcome],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Add My Own EPUB')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _running || result != null
                  ? LibraryAcquisitionProgressView(result: result)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Choose a single EPUB file from this device. It '
                          'will be copied into your library and prepared '
                          'automatically.',
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _pickAndImport,
                          child: const Text('Choose an EPUB'),
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
