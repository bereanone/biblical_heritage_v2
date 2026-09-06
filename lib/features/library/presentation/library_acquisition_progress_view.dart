import 'package:flutter/material.dart';

import '../../utilities/presentation/big_progress_bar.dart';
import '../data/library_acquisition_batch_runner.dart';
import 'library_acquisition_status_text.dart';

/// The one shared progress/result presentation for every setup/acquisition
/// screen (EGW download, Pioneer import, individual EPUB). Screens hand it
/// either an in-flight [progress] update or a finished [result] — neither
/// screen re-implements its own progress bar, summary line, or error-text
/// mapping.
///
/// Raw [LibraryAcquisitionOutcome.technicalDetail] is only ever shown
/// inside the collapsed "Advanced Details" disclosure, never by default.
class LibraryAcquisitionProgressView extends StatelessWidget {
  const LibraryAcquisitionProgressView({
    super.key,
    this.progress,
    this.result,
    this.onCancel,
    this.onRetryFailed,
    this.onDone,
    this.doneLabel = 'Done',
  });

  /// An in-flight batch update; null once the batch has finished.
  final LibraryAcquisitionBatchProgress? progress;

  /// The finished batch result; null while still running.
  final LibraryAcquisitionBatchResult? result;

  /// Shown only while [progress] is non-null. Omit to make this step
  /// non-cancellable (e.g. a single-file operation that is already atomic
  /// and near-instant).
  final VoidCallback? onCancel;

  /// Shown only when [result] has at least one unavailable outcome.
  final VoidCallback? onRetryFailed;

  /// Shown once [result] is non-null, as the primary way to leave this
  /// screen. Without it, a fully successful batch leaves the screen on a
  /// dead-end summary with no next step but the app bar's back arrow.
  final VoidCallback? onDone;

  /// Label for the [onDone] button.
  final String doneLabel;

  @override
  Widget build(BuildContext context) {
    final activeProgress = progress;
    final finished = result;

    if (finished != null) {
      return _ResultView(
        result: finished,
        onRetryFailed: onRetryFailed,
        onDone: onDone,
        doneLabel: doneLabel,
      );
    }
    if (activeProgress != null) {
      return _InProgressView(progress: activeProgress, onCancel: onCancel);
    }
    return const SizedBox.shrink();
  }
}

class _InProgressView extends StatelessWidget {
  const _InProgressView({required this.progress, this.onCancel});

  final LibraryAcquisitionBatchProgress progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final label = libraryAcquisitionProgressLabel(
      phase: progress.phase,
      title: progress.currentTitle,
    );
    final double? progressValue = progress.total > 0
        ? (progress.current / progress.total).clamp(0.0, 1.0)
        : null;
    final int? percent = progressValue == null
        ? null
        : (progressValue * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          progress.total > 0
              ? '$label (${progress.current} of ${progress.total})'
              : label,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        BigProgressBar(value: progressValue),
        const SizedBox(height: 12),
        Text(
          percent != null ? '$percent%' : 'Preparing…',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        if (onCancel != null) ...[
          const SizedBox(height: 12),
          Center(
            child: TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ),
        ],
      ],
    );
  }
}

class _ResultView extends StatefulWidget {
  const _ResultView({
    required this.result,
    this.onRetryFailed,
    this.onDone,
    this.doneLabel = 'Done',
  });

  final LibraryAcquisitionBatchResult result;
  final VoidCallback? onRetryFailed;
  final VoidCallback? onDone;
  final String doneLabel;

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView> {
  bool _showAdvancedDetails = false;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final unavailable = result.unavailableOutcomes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          libraryAcquisitionBatchSummary(result),
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (unavailable.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...unavailable.map(
            (outcome) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '• ${libraryAcquisitionFriendlyText(outcome)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          if (widget.onRetryFailed != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: widget.onRetryFailed,
              child: const Text('Retry Failed Books'),
            ),
          ],
          const SizedBox(height: 8),
          _AdvancedDetailsToggle(
            expanded: _showAdvancedDetails,
            onToggle: () =>
                setState(() => _showAdvancedDetails = !_showAdvancedDetails),
          ),
          if (_showAdvancedDetails)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: unavailable
                    .where((o) => (o.technicalDetail ?? '').trim().isNotEmpty)
                    .map(
                      (o) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: SelectableText(
                          '${o.libraryItemId}: ${o.technicalDetail}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
        if (widget.onDone != null) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: widget.onDone,
            child: Text(widget.doneLabel),
          ),
        ],
      ],
    );
  }
}

class _AdvancedDetailsToggle extends StatelessWidget {
  const _AdvancedDetailsToggle({
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onToggle,
      icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
      label: Text(expanded ? 'Hide Advanced Details' : 'Advanced Details'),
    );
  }
}
