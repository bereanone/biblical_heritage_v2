import 'package:flutter/material.dart';

class ViewerHeadingBlock extends StatelessWidget {
  const ViewerHeadingBlock({
    super.key,
    required this.text,
    required this.fontScale,
  });

  final String text;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final baseStyle =
        theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final style = baseStyle.copyWith(
      fontSize: 15 * fontScale,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.italic,
      height: 1.3,
    );

    return SelectionContainer.disabled(
      child: IgnorePointer(
        ignoring: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          color: theme.colorScheme.surfaceContainerHigh,
          child: Center(
            child: Text(text, textAlign: TextAlign.center, style: style),
          ),
        ),
      ),
    );
  }
}
