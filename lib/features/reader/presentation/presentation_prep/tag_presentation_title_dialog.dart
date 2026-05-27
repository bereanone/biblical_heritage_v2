import 'package:flutter/material.dart';

class TagPresentationHeaderFooterDraft {
  const TagPresentationHeaderFooterDraft({
    required this.topHeaderText,
    required this.bottomFooterText,
  });

  final String topHeaderText;
  final String bottomFooterText;
}

Future<TagPresentationHeaderFooterDraft?> showTagPresentationTitleDialog(
  BuildContext context, {
  String? topHeaderText,
  String? bottomFooterText,
}) {
  return showDialog<TagPresentationHeaderFooterDraft>(
    context: context,
    builder: (context) {
      return _TagPresentationHeaderFooterDialog(
        topHeaderText: topHeaderText,
        bottomFooterText: bottomFooterText,
      );
    },
  );
}

class _TagPresentationHeaderFooterDialog extends StatefulWidget {
  const _TagPresentationHeaderFooterDialog({
    this.topHeaderText,
    this.bottomFooterText,
  });

  final String? topHeaderText;
  final String? bottomFooterText;

  @override
  State<_TagPresentationHeaderFooterDialog> createState() =>
      _TagPresentationHeaderFooterDialogState();
}

class _TagPresentationHeaderFooterDialogState
    extends State<_TagPresentationHeaderFooterDialog> {
  late final TextEditingController _topController;
  late final TextEditingController _bottomController;

  @override
  void initState() {
    super.initState();
    _topController = TextEditingController(text: widget.topHeaderText ?? '');
    _bottomController = TextEditingController(
      text: widget.bottomFooterText ?? '',
    );
  }

  @override
  void dispose() {
    _topController.dispose();
    _bottomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Header / Footer'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _topController,
              autofocus: true,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Top title/header',
                hintText: 'Top title/header',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _bottomController,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Bottom title/footer',
                hintText: 'Bottom title/footer',
              ),
              onSubmitted: (_) => _submit(context),
            ),
            const SizedBox(height: 10),
            Text(
              'These fields live outside the content grid and appear in preview/presentation only when filled.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _submit(context),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  void _submit(BuildContext context) {
    Navigator.of(context).pop(
      TagPresentationHeaderFooterDraft(
        topHeaderText: _topController.text.trim(),
        bottomFooterText: _bottomController.text.trim(),
      ),
    );
  }
}
