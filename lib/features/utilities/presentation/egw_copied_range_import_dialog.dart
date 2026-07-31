import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/egw_copied_range_parser.dart';
import '../data/pioneer_source_catalog.dart';
import '../data/pioneer_text_import_service.dart';

class EgwCopiedRangeImportDialog extends StatefulWidget {
  const EgwCopiedRangeImportDialog({
    super.key,
    required this.work,
    required this.importService,
  });

  final PioneerSourceWork work;
  final PioneerTextImportService importService;

  @override
  State<EgwCopiedRangeImportDialog> createState() =>
      _EgwCopiedRangeImportDialogState();
}

class _EgwCopiedRangeImportDialogState
    extends State<EgwCopiedRangeImportDialog> {
  final TextEditingController _textController = TextEditingController();
  EgwCopiedRangeParseResult? _preview;
  bool _busy = false;
  String? _statusText;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      setState(() {
        _statusText = 'Clipboard is empty.';
      });
      return;
    }
    setState(() {
      _textController.text = text;
      _preview = null;
      _statusText = 'Pasted ${text.length} characters from the clipboard.';
    });
  }

  void _parsePreview() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _statusText = 'Paste copied EGW text before previewing.';
        _preview = null;
      });
      return;
    }
    final preview = parseEgwCopiedRangeText(
      text,
      workAbbreviation: widget.work.abbreviation.trim().isNotEmpty
          ? widget.work.abbreviation.trim()
          : 'DAR',
    );
    setState(() {
      _preview = preview;
      _statusText = preview.report.isValid
          ? 'Preview ready.'
          : 'Preview has warnings. Check the list below before importing.';
    });
  }

  Future<void> _importParsedRange() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _statusText = 'Paste copied EGW text before importing.';
      });
      return;
    }
    final preview =
        _preview ??
        parseEgwCopiedRangeText(
          text,
          workAbbreviation: widget.work.abbreviation.trim().isNotEmpty
              ? widget.work.abbreviation.trim()
              : 'DAR',
        );
    if (preview.report.paragraphCount == 0) {
      setState(() {
        _preview = preview;
        _statusText = 'No paragraph refs were detected.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _statusText = 'Importing parsed range...';
      _preview = preview;
    });

    try {
      final sourceUrl = _copiedRangeSourceUrl(widget.work);
      final result = await widget.importService.importFromCopiedRange(
        work: widget.work,
        text: text,
        sourceUrl: sourceUrl,
        sourceLabel: widget.work.sourceSiteLabel,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusText = 'Import failed: $error';
      });
    }
  }

  String? _copiedRangeSourceUrl(PioneerSourceWork work) {
    final preferredCaptureUrl = work.preferredCaptureCandidate?.url?.trim();
    if (preferredCaptureUrl != null && preferredCaptureUrl.isNotEmpty) {
      return preferredCaptureUrl;
    }

    final readerUrl = work.readerUrl?.trim();
    if (readerUrl != null && readerUrl.isNotEmpty) {
      return readerUrl;
    }

    final captureUrl = work.captureUrl?.trim();
    if (captureUrl != null && captureUrl.isNotEmpty) {
      return captureUrl;
    }

    final sourceUrl = work.sourceUrl?.trim();
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      return sourceUrl;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = _preview?.report;
    return AlertDialog(
      title: const Text('Import EGW Copied Range'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.work.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text('Abbreviation: ${widget.work.abbreviation}'),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                maxLines: 14,
                minLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  labelText: 'Paste copied EGW text here',
                ),
                onChanged: (_) {
                  if (_preview != null) {
                    setState(() {
                      _preview = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _pasteFromClipboard,
                    child: const Text('Paste from Clipboard'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _parsePreview,
                    child: const Text('Parse Preview'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _importParsedRange,
                    child: const Text('Import Parsed Range'),
                  ),
                ],
              ),
              if (_statusText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _statusText!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (report != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Preview',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _PreviewLine(
                  label: 'Heading count',
                  value: '${report.headingCount}',
                ),
                _PreviewLine(
                  label: 'Paragraph count',
                  value: '${report.paragraphCount}',
                ),
                _PreviewLine(
                  label: 'First ref',
                  value: report.firstRef ?? 'None',
                ),
                _PreviewLine(
                  label: 'Last ref',
                  value: report.lastRef ?? 'None',
                ),
                _PreviewLine(
                  label: 'Duplicate refs',
                  value: report.duplicateRefs.isEmpty
                      ? 'None'
                      : report.duplicateRefs.join(', '),
                ),
                _PreviewLine(
                  label: 'Warnings',
                  value: report.warnings.isEmpty
                      ? 'None'
                      : report.warnings.join(' | '),
                ),
                const SizedBox(height: 8),
                Text(
                  'First 10 refs/snippets',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final sample in report.sampleParagraphs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SelectableText('${sample.ref}: ${sample.snippet}'),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: $value'),
    );
  }
}
