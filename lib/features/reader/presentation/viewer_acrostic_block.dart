import 'package:flutter/material.dart';

class ViewerAcrosticBlock extends StatelessWidget {
  const ViewerAcrosticBlock({
    super.key,
    required this.hebrew,
    required this.transliteration,
    required this.fontScale,
  });

  final String hebrew;
  final String transliteration;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseSize = 15 * fontScale;
    final hebrewStyle = TextStyle(
      fontSize: baseSize * 1.5,
      fontWeight: FontWeight.w500,
      fontFamily: 'SBLHebrew',
      color: theme.colorScheme.onSurface,
      height: 1.15,
    );
    final translitStyle = TextStyle(
      fontSize: baseSize,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.onSurface,
      height: 1.15,
    );

    final spans = <InlineSpan>[];
    if (hebrew.trim().isNotEmpty) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Text(hebrew.trim(), style: hebrewStyle),
          ),
        ),
      );
    }
    if (hebrew.trim().isNotEmpty && transliteration.trim().isNotEmpty) {
      spans.add(const TextSpan(text: ' '));
    }
    if (transliteration.trim().isNotEmpty) {
      spans.add(TextSpan(text: transliteration.trim(), style: translitStyle));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: '-', style: translitStyle));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Center(
        child: Text.rich(
          TextSpan(children: spans),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        ),
      ),
    );
  }
}
