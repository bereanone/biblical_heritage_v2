import 'package:flutter/material.dart';

import 'presentation_prep/presentation_ui_helpers.dart';
import 'viewer_reference_title.dart';
import 'reader_tag_button.dart';
import 'viewer_search_models.dart';

// SBL-style abbreviations used on phone/narrow layouts.
String _phoneBookAbbr(String bookName) {
  const abbr = <String, String>{
    'Genesis': 'Gen',
    'Exodus': 'Exod',
    'Leviticus': 'Lev',
    'Numbers': 'Num',
    'Deuteronomy': 'Deut',
    'Joshua': 'Josh',
    'Judges': 'Judg',
    'Ruth': 'Ruth',
    '1 Samuel': '1 Sam',
    '2 Samuel': '2 Sam',
    '1 Kings': '1 Kgs',
    '2 Kings': '2 Kgs',
    '1 Chronicles': '1 Chr',
    '2 Chronicles': '2 Chr',
    'Ezra': 'Ezra',
    'Nehemiah': 'Neh',
    'Esther': 'Esth',
    'Job': 'Job',
    'Psalms': 'Ps',
    'Proverbs': 'Prov',
    'Ecclesiastes': 'Eccl',
    'Song of Solomon': 'Song',
    'Isaiah': 'Isa',
    'Jeremiah': 'Jer',
    'Lamentations': 'Lam',
    'Ezekiel': 'Ezek',
    'Daniel': 'Dan',
    'Hosea': 'Hos',
    'Joel': 'Joel',
    'Amos': 'Amos',
    'Obadiah': 'Obad',
    'Jonah': 'Jonah',
    'Micah': 'Mic',
    'Nahum': 'Nah',
    'Habakkuk': 'Hab',
    'Zephaniah': 'Zeph',
    'Haggai': 'Hag',
    'Zechariah': 'Zech',
    'Malachi': 'Mal',
    'Matthew': 'Matt',
    'Mark': 'Mark',
    'Luke': 'Luke',
    'John': 'John',
    'Acts': 'Acts',
    'Romans': 'Rom',
    '1 Corinthians': '1 Cor',
    '2 Corinthians': '2 Cor',
    'Galatians': 'Gal',
    'Ephesians': 'Eph',
    'Philippians': 'Phil',
    'Colossians': 'Col',
    '1 Thessalonians': '1 Thess',
    '2 Thessalonians': '2 Thess',
    '1 Timothy': '1 Tim',
    '2 Timothy': '2 Tim',
    'Titus': 'Titus',
    'Philemon': 'Phlm',
    'Hebrews': 'Heb',
    'James': 'Jas',
    '1 Peter': '1 Pet',
    '2 Peter': '2 Pet',
    '1 John': '1 John',
    '2 John': '2 John',
    '3 John': '3 John',
    'Jude': 'Jude',
    'Revelation': 'Rev',
  };
  return abbr[bookName] ?? bookName;
}

class ViewerTopBar extends StatelessWidget {
  const ViewerTopBar({
    super.key,
    required this.bookName,
    required this.chapter,
    required this.verse,
    required this.fontScale,
    required this.baseBibleFontSize,
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
  final double baseBibleFontSize;
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
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    return isWide ? _buildWide(context) : _buildPhone(context);
  }

  // ─── Phone / narrow layout ───────────────────────────────────────────────

  Widget _buildPhone(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 420;
    final actionExtent = compact ? 44.0 : 46.0;
    final inset = compact ? 6.0 : 10.0;
    final iconSize = presentationScaledSize(
      context,
      21,
      fontScale,
      min: 20,
      max: 26,
    );
    final titleStyle =
        theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ) ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.w700);

    final shortName = _phoneBookAbbr(bookName);
    final titleText =
        verse != null ? '$shortName $chapter:$verse' : '$shortName $chapter';

    // Compute cluster widths for the one-row threshold check.
    // Tag button size mirrors ReaderTagButtons' internal buttonExtent.
    final tagButtonSize = presentationScaledSize(
      context,
      compact ? 40 : 42,
      fontScale,
      min: 40,
      max: 52,
    );
    // Right cluster: # | Topics | !
    final rightW = tagButtonSize + 4 + actionExtent + 4 + tagButtonSize;
    // Left cluster: back + search + optional search-nav (estimated at 120px).
    final leftW =
        actionExtent * 2 + (_showBibleSearchNavigator ? 8 + 120.0 : 0);
    const minTitleW = 60.0;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final avail = constraints.maxWidth - 2 * inset;
        final fitsOneRow = leftW + rightW + minTitleW <= avail;

        return Material(
          color: theme.colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: fitsOneRow
                ? _phoneSingleRow(
                    ctx,
                    actionExtent: actionExtent,
                    inset: inset,
                    iconSize: iconSize,
                    titleStyle: titleStyle,
                    titleText: titleText,
                    compact: compact,
                  )
                : _phoneTwoRows(
                    ctx,
                    actionExtent: actionExtent,
                    inset: inset,
                    iconSize: iconSize,
                    titleStyle: titleStyle,
                    titleText: titleText,
                    compact: compact,
                  ),
          ),
        );
      },
    );
  }

  Widget _phoneSingleRow(
    BuildContext context, {
    required double actionExtent,
    required double inset,
    required double iconSize,
    required TextStyle titleStyle,
    required String titleText,
    required bool compact,
  }) {
    return SizedBox(
      height: kToolbarHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: Row(
          children: [
            ..._leftButtons(context, actionExtent: actionExtent, iconSize: iconSize, compact: compact),
            Expanded(child: _titleInkWell(titleText, titleStyle)),
            ..._rightButtons(context, actionExtent: actionExtent, iconSize: iconSize),
          ],
        ),
      ),
    );
  }

  // Two-row portrait layout: row 1 = navigation + title, row 2 = action buttons.
  Widget _phoneTwoRows(
    BuildContext context, {
    required double actionExtent,
    required double inset,
    required double iconSize,
    required TextStyle titleStyle,
    required String titleText,
    required bool compact,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: kToolbarHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Row(
              children: [
                ..._leftButtons(context, actionExtent: actionExtent, iconSize: iconSize, compact: compact),
                Expanded(child: _titleInkWell(titleText, titleStyle)),
              ],
            ),
          ),
        ),
        SizedBox(
          height: kToolbarHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: _rightButtons(context, actionExtent: actionExtent, iconSize: iconSize),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _leftButtons(
    BuildContext context, {
    required double actionExtent,
    required double iconSize,
    required bool compact,
  }) {
    return [
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
        const SizedBox(width: 8),
        _BibleSearchNavigator(
          session: bibleSearchSession!,
          compact: compact,
          onPrevious: onPreviousBibleSearchHit,
          onNext: onNextBibleSearchHit,
        ),
      ],
    ];
  }

  // Right cluster for phone: # | Topics | !
  List<Widget> _rightButtons(
    BuildContext context, {
    required double actionExtent,
    required double iconSize,
  }) {
    return [
      ReaderTagButtons(
        fontScale: fontScale,
        activeFamily: activeFamily,
        showStandard: true,
        showDollar: false,
        showRapid: false,
        onStandardTap: onStandardTag,
        onDollarTap: onDollarTag,
        onRapidTap: onRapidTag,
      ),
      const SizedBox(width: 4),
      IconButton(
        constraints: BoxConstraints.tightFor(
          width: actionExtent,
          height: actionExtent,
        ),
        padding: EdgeInsets.zero,
        onPressed: onTopics,
        icon: Icon(Icons.list_alt, size: iconSize),
        tooltip: 'Topics',
      ),
      const SizedBox(width: 4),
      ReaderTagButtons(
        fontScale: fontScale,
        activeFamily: activeFamily,
        showStandard: false,
        showDollar: false,
        showRapid: true,
        onStandardTap: onStandardTag,
        onDollarTap: onDollarTag,
        onRapidTap: onRapidTag,
      ),
    ];
  }

  Widget _titleInkWell(String titleText, TextStyle titleStyle) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onChoosePassage,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          titleText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: titleStyle,
        ),
      ),
    );
  }

  // ─── Wide layout (iPad / macOS) ───────────────────────────────────────────

  // Keeps the safe presLeft clamp from commit 256b35c.
  // Presentation cluster (connected_tv + slideshow) is shown only here.
  Widget _buildWide(BuildContext context) {
    final theme = Theme.of(context);
    const actionExtent = 48.0;
    const inset = 10.0;
    final baseTitleStyle =
        theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ) ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
    final readingFontSize =
        (theme.textTheme.bodyLarge?.fontSize ?? 16) * fontScale;
    final iconSize = presentationScaledSize(
      context,
      23,
      fontScale,
      min: 20,
      max: 26,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth;
        final titleWidth = (barWidth * 0.30).clamp(72.0, 320.0);
        final halfBar = barWidth / 2.0;
        final halfTitle = titleWidth / 2.0;
        const clusterGap = 20.0;
        final presClusterW = 2.0 * actionExtent + 8.0;

        // Safe clamp: narrow bars can produce lower > upper; clamp lower first.
        final presClampMax =
            (halfBar - presClusterW).clamp(0.0, double.infinity);
        final presClampMin =
            (24.0 + 2.0 * actionExtent + 8.0).clamp(0.0, presClampMax);
        final presLeft = (halfBar - halfTitle - clusterGap - presClusterW)
            .clamp(presClampMin, presClampMax);
        final tagLeft = halfBar + halfTitle + clusterGap;

        return Material(
          color: theme.colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: kToolbarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: inset),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: 24,
                      top: 0,
                      bottom: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
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
                            const SizedBox(width: 16),
                            _BibleSearchNavigator(
                              session: bibleSearchSession!,
                              compact: false,
                              onPrevious: onPreviousBibleSearchHit,
                              onNext: onNextBibleSearchHit,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.center,
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
                    Positioned(
                      left: presLeft,
                      top: 0,
                      bottom: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                          IconButton(
                            constraints: BoxConstraints.tightFor(
                              width: actionExtent,
                              height: actionExtent,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: onDollarTag,
                            icon: Icon(
                              Icons.slideshow_outlined,
                              size: iconSize,
                            ),
                            tooltip: 'Presentation Setup',
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: tagLeft,
                      top: 0,
                      bottom: 0,
                      child: ReaderTagButtons(
                        fontScale: fontScale,
                        activeFamily: activeFamily,
                        showDollar: false,
                        onStandardTap: onStandardTag,
                        onDollarTap: onDollarTag,
                        onRapidTap: onRapidTag,
                      ),
                    ),
                    Positioned(
                      right: 24,
                      top: 0,
                      bottom: 0,
                      child: IconButton(
                        constraints: BoxConstraints.tightFor(
                          width: actionExtent,
                          height: actionExtent,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: onTopics,
                        icon: Icon(Icons.list_alt, size: iconSize),
                      ),
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
      fontWeight: FontWeight.w600,
      fontSize: compact ? 18 : 19,
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
              icon: Text(
                '<',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 20 : 21,
                  height: 1,
                ),
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: compact ? 30 : 32,
                height: compact ? 30 : 32,
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
              icon: Text(
                '>',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 20 : 21,
                  height: 1,
                ),
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: compact ? 30 : 32,
                height: compact ? 30 : 32,
              ),
              color: foreground,
            ),
          ],
        ),
      ),
    );
  }
}
