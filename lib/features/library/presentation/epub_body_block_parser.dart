part of 'library_book_reader_screen.dart';

class _ReaderHeadingTarget {
  const _ReaderHeadingTarget({required this.key, required this.offset});

  final String key;
  final double offset;
}

class _SectionBlockView extends StatelessWidget {
  const _SectionBlockView({
    super.key,
    required this.block,
    required this.textColor,
    required this.bodyFontSize,
    required this.topPadding,
    required this.bottomPadding,
    required this.isNightMode,
  });

  final LibraryBookBlock block;
  final Color textColor;
  final double bodyFontSize;
  final double topPadding;
  final double bottomPadding;
  final bool isNightMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHeading = block.isHeading;
    final isBlockquote = block.isBlockquote;
    final className = block.className ?? '';
    final isChapterTitle = isHeading && _hasEpubClass(className, 'chapterhead');
    final isSectionTitle = isHeading && _hasEpubClass(className, 'sectionhead');
    final isDevotionalLead =
        _hasEpubClass(className, 'devotionaltext') ||
        _hasEpubClass(className, 'bibletext') ||
        _hasEpubClass(className, 'center');
    final fontSize = isChapterTitle
        ? bodyFontSize * 1.95
        : isHeading
        ? bodyFontSize * _headingFontScale(block.headingLevel)
        : isDevotionalLead
        ? bodyFontSize * 1.02
        : bodyFontSize;
    final textAlign = isChapterTitle || isSectionTitle || isDevotionalLead
        ? TextAlign.center
        : TextAlign.start;
    final style =
        (isChapterTitle
                ? theme.textTheme.headlineSmall
                : isHeading
                ? theme.textTheme.titleMedium
                : theme.textTheme.bodyLarge)
            ?.copyWith(
              color: textColor,
              fontWeight: isChapterTitle || isSectionTitle || isDevotionalLead
                  ? FontWeight.w800
                  : isHeading
                  ? FontWeight.w700
                  : FontWeight.w400,
              fontSize: fontSize,
              height: isChapterTitle
                  ? 1.12
                  : isHeading
                  ? 1.35
                  : isDevotionalLead
                  ? 1.45
                  : isBlockquote
                  ? 1.7
                  : 1.6,
              fontStyle: isBlockquote ? FontStyle.italic : null,
            );
    final resolvedStyle =
        style ??
        theme.textTheme.bodyLarge?.copyWith(color: textColor) ??
        TextStyle(color: textColor, fontSize: bodyFontSize, height: 1.6);
    final textSpan = TextSpan(
      style: resolvedStyle,
      children: _buildEpubInlineSpans(
        html: block.html,
        fallbackText: block.text,
        baseStyle: resolvedStyle,
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: isBlockquote
              ? Border(
                  left: BorderSide(
                    color: _readerBorderColor(
                      theme,
                      isNightMode,
                    ).withValues(alpha: 0.65),
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.only(left: isBlockquote ? 12 : 0),
          child: SelectableText.rich(textSpan, textAlign: textAlign),
        ),
      ),
    );
  }
}
