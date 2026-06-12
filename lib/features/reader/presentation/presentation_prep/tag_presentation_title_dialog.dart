import 'package:flutter/material.dart';

import 'presentation_ui_helpers.dart';

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
  required double fontScale,
  String? topHeaderText,
  String? bottomFooterText,
}) {
  return showDialog<TagPresentationHeaderFooterDraft>(
    context: context,
    builder: (context) {
      return _TagPresentationHeaderFooterDialog(
        fontScale: fontScale,
        topHeaderText: topHeaderText,
        bottomFooterText: bottomFooterText,
      );
    },
  );
}

class _TagPresentationHeaderFooterDialog extends StatefulWidget {
  const _TagPresentationHeaderFooterDialog({
    required this.fontScale,
    this.topHeaderText,
    this.bottomFooterText,
  });

  final double fontScale;
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
    final inputStyle = presentationTextStyle(
      context,
      theme.textTheme.bodyMedium,
      widget.fontScale,
      minFontSize: 15,
      maxFontSize: 19,
    );
    final fieldLabelStyle = presentationTextStyle(
      context,
      theme.textTheme.labelLarge,
      widget.fontScale,
      fontWeight: FontWeight.w700,
      minFontSize: 13.5,
      maxFontSize: 17.5,
    );
    final fieldHintStyle = presentationTextStyle(
      context,
      theme.textTheme.bodySmall,
      widget.fontScale,
      color: theme.colorScheme.outline,
      minFontSize: 12.5,
      maxFontSize: 16,
    );
    return AlertDialog(
      title: Text(
        'Header / Footer',
        style: presentationTextStyle(
          context,
          theme.textTheme.titleMedium,
          widget.fontScale,
          fontWeight: FontWeight.w700,
          minFontSize: 16,
          maxFontSize: 22,
        ),
      ),
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
              style: inputStyle,
              decoration: InputDecoration(
                labelText: 'Top title/header',
                hintText: 'Top title/header',
                labelStyle: fieldLabelStyle,
                hintStyle: fieldHintStyle,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _bottomController,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.done,
              style: inputStyle,
              decoration: InputDecoration(
                labelText: 'Bottom title/footer',
                hintText: 'Bottom title/footer',
                labelStyle: fieldLabelStyle,
                hintStyle: fieldHintStyle,
              ),
              onSubmitted: (_) => _submit(context),
            ),
            const SizedBox(height: 10),
            Text(
              'These fields live outside the content grid and appear in preview/presentation only when filled.',
              style: presentationTextStyle(
                context,
                theme.textTheme.bodySmall,
                widget.fontScale,
                color: theme.colorScheme.outline,
                minFontSize: 12.5,
                maxFontSize: 16,
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
