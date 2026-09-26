part of 'library_book_reader_screen.dart';

/// Compact previous/next navigation used by both library-search result bars.
class _SearchHitNavigator extends StatelessWidget {
  const _SearchHitNavigator({
    required this.label,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
  });

  final String label;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = libraryControlTextStyle(
      context,
      theme.textTheme.labelLarge,
      fontWeight: FontWeight.w800,
      color: textColor,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: canGoPrevious ? onPrevious : null,
              icon: const Icon(Icons.chevron_left),
              color: textColor,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              tooltip: 'Previous hit',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(label, style: labelStyle),
            ),
            IconButton(
              onPressed: canGoNext ? onNext : null,
              icon: const Icon(Icons.chevron_right),
              color: textColor,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              tooltip: 'Next hit',
            ),
          ],
        ),
      ),
    );
  }
}
