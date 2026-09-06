import 'package:flutter/material.dart';

import '../../utilities/presentation/elibrary_setup_screen.dart';
import '../data/library_acquisition_batch_runner.dart';
import '../data/library_setup_invitation_service.dart';
import 'library_acquisition_progress_view.dart';

/// "Download Ellen White Library" — Phase 2's minimal wrapper around the
/// existing official-download selection screen. It does not redesign that
/// screen; it reuses it unmodified for "choose which collections/formats",
/// then replaces the old manual "go find Index Now" step with an automatic
/// orchestrated prepare pass once the user returns from it.
class DownloadEllenWhiteLibraryScreen extends StatefulWidget {
  const DownloadEllenWhiteLibraryScreen({super.key});

  @override
  State<DownloadEllenWhiteLibraryScreen> createState() =>
      _DownloadEllenWhiteLibraryScreenState();
}

class _DownloadEllenWhiteLibraryScreenState
    extends State<DownloadEllenWhiteLibraryScreen> {
  bool _running = false;
  bool _cancelled = false;
  LibraryAcquisitionBatchProgress? _progress;
  LibraryAcquisitionBatchResult? _result;

  Future<void> _openSelectionThenPrepare() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ELibrarySetupScreen()),
    );
    if (!mounted) return;
    await _prepare();
  }

  Future<void> _prepare({List<LibraryAcquisitionBatchTarget>? only}) async {
    setState(() {
      _running = true;
      _cancelled = false;
      _result = null;
      _progress = null;
    });
    final targets =
        only ??
        await LibraryAcquisitionBatchRunner.instance
            .loadPendingOfficialDownloadItems();
    final result = await LibraryAcquisitionBatchRunner.instance.activate(
      targets,
      onProgress: (progress) {
        if (mounted) setState(() => _progress = progress);
      },
      shouldContinue: () => !_cancelled,
    );
    if (!mounted) return;
    if (result.readyCount > 0) {
      await LibrarySetupInvitationService.instance.markCompleted();
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _progress = null;
      _result = result;
    });
  }

  void _cancel() => _cancelled = true;

  void _retryFailed() {
    final failed =
        _result?.failedTargets ?? const <LibraryAcquisitionBatchTarget>[];
    if (failed.isEmpty) return;
    _prepare(only: failed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Download Ellen White Library')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _running || _result != null
                  ? LibraryAcquisitionProgressView(
                      progress: _progress,
                      result: _result,
                      onCancel: _running ? _cancel : null,
                      onRetryFailed: _retryFailed,
                      onDone: _running
                          ? null
                          : () => Navigator.of(context).pop(),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Choose which official Ellen White writings '
                          'collections you want. We will download them and '
                          'get them ready to read automatically.',
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _openSelectionThenPrepare,
                          child: const Text('Choose Books to Download'),
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
