import 'package:flutter/material.dart';

import 'presentation_ui_helpers.dart';

class TagPresentationPrepEmptyState extends StatelessWidget {
  const TagPresentationPrepEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.fontScale = 1.0,
    this.hint,
  });

  final String title;
  final String message;
  final double fontScale;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: presentationTextStyle(
                    context,
                    theme.textTheme.titleMedium,
                    fontScale,
                    fontWeight: FontWeight.w700,
                    minFontSize: 17,
                    maxFontSize: 24,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: presentationTextStyle(
                    context,
                    theme.textTheme.bodyMedium,
                    fontScale,
                    minFontSize: 14,
                    maxFontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (hint != null && hint!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    hint!,
                    style: presentationTextStyle(
                      context,
                      theme.textTheme.bodyMedium,
                      fontScale,
                      color: theme.colorScheme.outline,
                      minFontSize: 13,
                      maxFontSize: 17,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
