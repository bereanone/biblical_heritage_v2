import 'package:flutter/material.dart';

import '../data/demo_download_service.dart';

class DemoDownloadScreen extends StatefulWidget {
  const DemoDownloadScreen({super.key});

  @override
  State<DemoDownloadScreen> createState() => _DemoDownloadScreenState();
}

class _DemoDownloadScreenState extends State<DemoDownloadScreen> {
  bool _running = false;
  bool _cancelRequested = false;
  DemoDownloadProgress? _progress;
  DemoDownloadReport? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startDownload();
    });
  }

  @override
  void dispose() {
    _cancelRequested = true;
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (_running) return;
    setState(() {
      _running = true;
      _cancelRequested = false;
      _error = null;
      _report = null;
    });

    try {
      final report = await DemoDownloadService.instance.run(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
        isCancelled: () => _cancelRequested,
      );
      if (!mounted) return;
      setState(() => _report = report);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Demo download finished in ${report.elapsedSeconds.toStringAsFixed(1)}s',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Demo download failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  void _cancelDownload() {
    if (!_running) return;
    setState(() => _cancelRequested = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = _progress;
    final report = _report;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo Download'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Full EGW collection download',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This temporary demo downloads all discovered EPUB and PDF files into LibraryRoot/TEST_Downloads only.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Destination: LibraryRoot/TEST_Downloads',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_running) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        progress?.statusMessage ?? 'Starting download...',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${progress?.currentCollection ?? 'Collection'} '
                        '${progress?.collectionIndex ?? 0}/${progress?.collectionTotal ?? 0}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Discovered: ${progress?.discoveredCount ?? 0}  '
                        'Downloaded: ${progress?.downloadedCount ?? 0}  '
                        'Skipped: ${progress?.skippedCount ?? 0}  '
                        'Failed: ${progress?.failedCount ?? 0}',
                      ),
                      const SizedBox(height: 4),
                      Text('Current file: ${progress?.currentFile ?? '-'}'),
                      const SizedBox(height: 4),
                      Text(
                        'Elapsed: ${(progress?.elapsedSeconds ?? 0).toStringAsFixed(1)}s',
                      ),
                    ] else if (report != null) ...[
                      Text(
                        'Completed in ${report.elapsedSeconds.toStringAsFixed(1)}s',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Downloaded: ${report.filesDownloaded.length}'),
                      Text('Skipped: ${report.filesSkipped.length}'),
                      Text('Failed: ${report.failures.length}'),
                      const SizedBox(height: 8),
                      SelectableText(report.reportFilePath),
                    ] else if (_error != null) ...[
                      Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ] else ...[
                      const Text('Preparing download...'),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: _running ? null : _startDownload,
                          child: Text(_report == null
                              ? 'Start Demo Download'
                              : 'Run Again'),
                        ),
                        OutlinedButton(
                          onPressed: _running ? _cancelDownload : null,
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
