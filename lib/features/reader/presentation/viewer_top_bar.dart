import 'package:flutter/material.dart';

import 'viewer_reference_title.dart';

class ViewerTopBar extends StatelessWidget {
  const ViewerTopBar({
    super.key,
    required this.bookName,
    required this.chapter,
    required this.verse,
    required this.fontScale,
    required this.onSearch,
    required this.onTopics,
    required this.onChoosePassage,
  });

  final String bookName;
  final int chapter;
  final int? verse;
  final double fontScale;
  final VoidCallback onSearch;
  final VoidCallback onTopics;
  final VoidCallback onChoosePassage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseTitleStyle = theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ) ??
        const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        );
    final readingFontSize =
        ((theme.textTheme.bodyLarge?.fontSize ?? 16) * fontScale);

    return LayoutBuilder(
      builder: (context, constraints) {
        const actionWidth = 48.0;
        const leadingActions = 2;
        const reservedTrailingActions = 2;
        const horizontalPadding = 8.0;
        final reservedWidth =
            (leadingActions + reservedTrailingActions) * actionWidth +
                (horizontalPadding * 2);
        final titleWidth = (constraints.maxWidth - reservedWidth).clamp(72.0, 420.0);

        return Material(
          color: theme.colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: kToolbarHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        IconButton(
                          onPressed: onSearch,
                          icon: const Icon(Icons.search),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: onTopics,
                          icon: const Icon(Icons.list_alt),
                        ),
                      ],
                    ),
                  ),
                  Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: onChoosePassage,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: SizedBox(
                          width: titleWidth,
                          child: ViewerReferenceTitle(
                            bookName: bookName,
                            chapter: chapter,
                            verse: verse,
                            baseStyle: baseTitleStyle,
                            minimumFontSize: readingFontSize,
                            maxWidth: titleWidth,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
