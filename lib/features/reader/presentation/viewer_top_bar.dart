import 'package:flutter/material.dart';

import 'presentation_prep/presentation_ui_helpers.dart';
import 'viewer_reference_title.dart';
import 'reader_tag_button.dart';

class ViewerTopBar extends StatelessWidget {
  const ViewerTopBar({
    super.key,
    required this.bookName,
    required this.chapter,
    required this.verse,
    required this.fontScale,
    required this.onSearch,
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
}
