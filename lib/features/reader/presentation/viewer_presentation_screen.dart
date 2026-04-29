import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tag_quick_apply_helper.dart';
import 'viewer_presentation_settings.dart';
import '../../../core/database/study_bible_database.dart';

class ViewerPresentationScreen extends StatefulWidget {
  const ViewerPresentationScreen({
    super.key,
    required this.entries,
    required this.initialIndex,
    required this.aspectRatioPreset,
  });

  final List<HashTagEntry> entries;
  final int initialIndex;
  final PresentationAspectRatioPreset aspectRatioPreset;

  @override
  State<ViewerPresentationScreen> createState() =>
      _ViewerPresentationScreenState();
}

class _ViewerPresentationScreenState extends State<ViewerPresentationScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, String> _bookNames = <int, String>{};
  int _index = 0;
  bool _loadingBooks = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.entries.length - 1);
    _loadBooks();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBooks() async {
    final books = await StudyBibleDatabase.instance.loadBooks();
    final names = {for (final book in books) book.bookNumber: book.bookName};
    if (!mounted) return;
    setState(() {
      _bookNames
        ..clear()
        ..addAll(names);
      _loadingBooks = false;
    });
  }

  HashTagEntry get _currentEntry => widget.entries[_index];

  bool _isNoteOnlyEntry(HashTagEntry entry) {
    return entry.bookNumber == 0 &&
        (entry.contentHtml?.trim().isNotEmpty == true ||
            entry.verseRef.startsWith('note:'));
  }

  int _noteNumberFor(HashTagEntry entry) {
    var count = 0;
    for (final current in widget.entries) {
      if (!_isNoteOnlyEntry(current)) continue;
      count++;
      if (current.id == entry.id) return count;
    }
    return 1;
  }

  bool get _canGoPrevious => _index > 0;
  bool get _canGoNext => _index < widget.entries.length - 1;

  void _previous() {
    if (!_canGoPrevious) return;
    setState(() {
      _index -= 1;
    });
    _scrollController.jumpTo(0);
  }

  void _next() {
    if (!_canGoNext) return;
    setState(() {
      _index += 1;
    });
    _scrollController.jumpTo(0);
  }

  String _referenceFor(HashTagEntry entry) {
    final bookName = _bookNames[entry.bookNumber] ?? 'Book ${entry.bookNumber}';
    if (_isNoteOnlyEntry(entry)) {
      return 'Note ${_noteNumberFor(entry)}';
    }
    return '$bookName ${entry.chapter}:${entry.verse}';
  }

  String _stripHtml(String input) {
    return input
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  String _bodyTextFor(HashTagEntry entry) {
    final noteHtml = entry.contentHtml?.trim() ?? '';
    if (noteHtml.isNotEmpty) {
      final noteText = _stripHtml(noteHtml);
      if (noteText.isNotEmpty) return noteText;
    }
    final verseText = entry.verseText.trim();
    return verseText.isNotEmpty ? verseText : entry.verseRef;
  }

  double _fitFontSize({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double maxHeight,
    required double minFontSize,
    required double maxFontSize,
    required TextDirection textDirection,
  }) {
    var low = minFontSize;
    var high = math.max(minFontSize, maxFontSize);
    var best = minFontSize;

    bool fits(double size) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style.copyWith(fontSize: size)),
        textDirection: textDirection,
        textAlign: TextAlign.left,
        maxLines: null,
      )..layout(maxWidth: maxWidth);
      return painter.height <= maxHeight;
    }

    if (!fits(minFontSize)) return minFontSize;

    while ((high - low) > 0.25) {
      final mid = (low + high) / 2;
      if (fits(mid)) {
        best = mid;
        low = mid;
      } else {
        high = mid;
      }
    }
    return best;
  }

  double _measureTextHeight({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required TextDirection textDirection,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textAlign: TextAlign.left,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = _currentEntry;
    final verseText = _bodyTextFor(entry);
    final referenceText = _referenceFor(entry);
    final background = const Color(0xFF0B0D11);
    final accent = const Color(0xFFE0BE87);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topLeft,
                    radius: 1.3,
                    colors: [Color(0xFF12151B), Color(0xFF090B0F)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 56, 16, 60),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final titleStyle = (theme.textTheme.titleMedium ??
                            const TextStyle())
                        .copyWith(
                          fontWeight: FontWeight.w800,
                          color: accent,
                          letterSpacing: 0.2,
                          height: 1.08,
                        );
                    final referenceWidth = math.max(
                      0.0,
                      constraints.maxWidth - 56,
                    );
                    final titleSize = _fitFontSize(
                      text: referenceText,
                      style: titleStyle,
                      maxWidth: referenceWidth,
                      maxHeight: 52,
                      minFontSize: 14,
                      maxFontSize: 24,
                      textDirection: Directionality.of(context),
                    );
                    final bodyStyle = (theme.textTheme.headlineSmall ??
                            const TextStyle())
                        .copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFF7F1E5),
                          height: 1.18,
                          letterSpacing: 0.1,
                        );
                    final verseMinFontSize = 18.0;
                    final verseMaxFontSize = math.min(
                      88.0,
                      math.max(56.0, constraints.maxWidth * 0.085),
                    );

                    final availableWidth = constraints.maxWidth;
                    final availableHeight = constraints.maxHeight;
                    final aspectRatio = widget.aspectRatioPreset.aspectRatio;
                    var panelWidth = availableWidth;
                    final panelHeight = availableHeight;
                    if (aspectRatio != null &&
                        aspectRatio.isFinite &&
                        aspectRatio > 0) {
                      final ratioWidth = panelHeight * aspectRatio;
                      if (ratioWidth <= availableWidth) {
                        panelWidth = ratioWidth;
                      }
                    }
                    panelWidth = panelWidth.clamp(280.0, availableWidth);

                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints.tightFor(
                          width: panelWidth,
                          height: panelHeight,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF14171D).withValues(
                              alpha: 0.96,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.32),
                              width: 1.1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 28,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    referenceText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: titleStyle.copyWith(
                                      fontSize: titleSize,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (context, bodyConstraints) {
                                        final bodyWidth = math.max(
                                          0.0,
                                          bodyConstraints.maxWidth,
                                        );
                                        final bodyHeight = math.max(
                                          0.0,
                                          bodyConstraints.maxHeight,
                                        );
                                        final chosenVerseSize = _fitFontSize(
                                          text: verseText,
                                          style: bodyStyle,
                                          maxWidth: bodyWidth,
                                          maxHeight: bodyHeight,
                                          minFontSize: verseMinFontSize,
                                          maxFontSize: verseMaxFontSize,
                                          textDirection:
                                              Directionality.of(context),
                                        );
                                        final needsScroll =
                                            _measureTextHeight(
                                              text: verseText,
                                              style: bodyStyle.copyWith(
                                                fontSize: verseMinFontSize,
                                              ),
                                              maxWidth: bodyWidth,
                                              textDirection:
                                                  Directionality.of(context),
                                            ) > bodyHeight;

                                        return Scrollbar(
                                          controller: _scrollController,
                                          thumbVisibility: needsScroll,
                                          child: SingleChildScrollView(
                                            controller: _scrollController,
                                            physics: needsScroll
                                                ? const ClampingScrollPhysics()
                                                : const NeverScrollableScrollPhysics(),
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                minHeight: bodyHeight,
                                              ),
                                              child: Align(
                                                alignment: Alignment.topLeft,
                                                child: Text(
                                                  verseText,
                                                  style: bodyStyle.copyWith(
                                                    fontSize: chosenVerseSize,
                                                  ),
                                                  textAlign: TextAlign.left,
                                                  softWrap: true,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: _PresenterControlButton(
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).maybePop(),
                foregroundColor: const Color(0xFF9AA1AB),
                borderColor: const Color(0xFF3A404A),
                tooltip: 'Back',
              ),
            ),
            Positioned(
              bottom: 14,
              left: 14,
              child: _PresenterControlButton(
                icon: Icons.chevron_left_rounded,
                onPressed: _canGoPrevious ? _previous : null,
                foregroundColor: const Color(0xFF9AA1AB),
                borderColor: const Color(0xFF3A404A),
                tooltip: 'Previous verse',
              ),
            ),
            Positioned(
              bottom: 14,
              right: 14,
              child: _PresenterControlButton(
                icon: Icons.chevron_right_rounded,
                onPressed: _canGoNext ? _next : null,
                foregroundColor: const Color(0xFF9AA1AB),
                borderColor: const Color(0xFF3A404A),
                tooltip: 'Next verse',
              ),
            ),
            if (_loadingBooks)
              const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

class _PresenterControlButton extends StatelessWidget {
  const _PresenterControlButton({
    required this.icon,
    required this.onPressed,
    required this.foregroundColor,
    required this.borderColor,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color foregroundColor;
  final Color borderColor;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF11151B).withValues(alpha: 0.98),
              border: Border.all(color: borderColor, width: 1.4),
            ),
            child: Icon(
              icon,
              size: 18,
              color: onPressed == null
                  ? foregroundColor.withValues(alpha: 0.7)
                  : foregroundColor,
            ),
          ),
        ),
      ),
    );
  }
}
