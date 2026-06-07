import 'package:flutter/material.dart';

import 'presentation_prep/presentation_ui_helpers.dart';
import 'viewer_reference_title.dart';
import 'reader_tag_button.dart';
import 'viewer_search_models.dart';

class ViewerTopBar extends StatelessWidget {
  const ViewerTopBar({
    super.key,
    required this.bookName,
    required this.chapter,
    required this.verse,
    required this.fontScale,
    required this.onSearch,
    this.bibleSearchSession,
    this.onPreviousBibleSearchHit,
    this.onNextBibleSearchHit,
    required this.onSavedPresentations,
    required this.onStandardTag,
    required this.onDollarTag,
    required this.onRapidTag,
    required this.activeFamily,
    required this.onTopics,
    required this.onChoosePassage,
  });

  final String bookName;
  final int chapter;
  final int? verse;
  final double fontScale;
  final VoidCallback onSearch;
  final BibleSearchSession? bibleSearchSession;
  final VoidCallback? onPreviousBibleSearchHit;
  final VoidCallback? onNextBibleSearchHit;
  final VoidCallback onSavedPresentations;
  final VoidCallback onStandardTag;
  final VoidCallback onDollarTag;
  final VoidCallback onRapidTag;
  final ReaderTagFamily? activeFamily;
  final VoidCallback onTopics;
  final VoidCallback onChoosePassage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 420;
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final actionExtent = isWide ? 48.0 : (compact ? 44.0 : 46.0);
    final inset = compact ? 6.0 : 10.0;
    final baseTitleStyle =
        theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ) ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
    final readingFontSize =
        ((theme.textTheme.bodyLarge?.fontSize ?? 16) * fontScale);
    final iconSize = presentationScaledSize(
      context,
      isWide ? 23 : 21,
      fontScale,
      min: 20,
      max: 26,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final titleWidth = (constraints.maxWidth * (isWide ? 0.30 : 0.34))
            .clamp(72.0, isWide ? 320.0 : 280.0);

        return Material(
          color: theme.colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: kToolbarHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: Row(
                  children: [
                    IconButton(
                      constraints: BoxConstraints.tightFor(
                        width: actionExtent,
                        height: actionExtent,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.arrow_back, size: iconSize),
                    ),
                    IconButton(
                      constraints: BoxConstraints.tightFor(
                        width: actionExtent,
                        height: actionExtent,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: onSearch,
                      icon: Icon(Icons.search, size: iconSize),
                    ),
                    if (_showBibleSearchNavigator) ...[
                      const SizedBox(width: 6),
                      _BibleSearchNavigator(
                        session: bibleSearchSession!,
                        compact: compact,
                        onPrevious: onPreviousBibleSearchHit,
                        onNext: onNextBibleSearchHit,
                      ),
                    ],
                    IconButton(
                      constraints: BoxConstraints.tightFor(
                        width: actionExtent,
                        height: actionExtent,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: onSavedPresentations,
                      icon: Icon(Icons.connected_tv, size: iconSize),
                      tooltip: 'Saved Presentations',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Center(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: onChoosePassage,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
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
                    ),
                    const SizedBox(width: 8),
                    ReaderTagButtons(
                      fontScale: fontScale,
                      activeFamily: activeFamily,
                      onStandardTap: onStandardTag,
                      onDollarTap: onDollarTag,
                      onRapidTap: onRapidTag,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      constraints: BoxConstraints.tightFor(
                        width: actionExtent,
                        height: actionExtent,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: onTopics,
                      icon: Icon(Icons.list_alt, size: iconSize),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _showBibleSearchNavigator =>
      bibleSearchSession != null && bibleSearchSession!.results.isNotEmpty;
}

class _BibleSearchNavigator extends StatelessWidget {
  const _BibleSearchNavigator({
    required this.session,
    required this.compact,
    required this.onPrevious,
    required this.onNext,
  });

  final BibleSearchSession session;
  final bool compact;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurface;
    final background = theme.colorScheme.surface;
    final borderColor = theme.dividerColor;
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w800,
      fontSize: compact ? 11 : 12,
      height: 1,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 6,
          vertical: compact ? 2 : 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: session.hasPrevious ? onPrevious : null,
              tooltip: 'Previous Bible search hit',
              icon: const Icon(Icons.chevron_left),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: compact ? 28 : 30,
                height: compact ? 28 : 30,
              ),
              color: foreground,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(session.counterLabel, style: labelStyle),
            ),
            IconButton(
              onPressed: session.hasNext ? onNext : null,
              tooltip: 'Next Bible search hit',
              icon: const Icon(Icons.chevron_right),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: compact ? 28 : 30,
                height: compact ? 28 : 30,
              ),
              color: foreground,
            ),
          ],
        ),
      ),
    );
  }
}
