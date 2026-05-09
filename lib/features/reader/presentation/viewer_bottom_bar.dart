import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_mode.dart';

part 'viewer_bottom_bar_buttons.dart';

class ViewerBottomBar extends StatelessWidget {
  const ViewerBottomBar({
    super.key,
    required this.themeMode,
    required this.onToggleThemeMode,
    required this.bookNumber,
    required this.interlinearEnabled,
    required this.onToggleInterlinear,
    required this.onMode,
    required this.onHistory,
    required this.onLibrary,
    required this.onDecreaseFont,
    required this.onIncreaseFont,
    required this.onCommentary,
    required this.onMarkup,
    required this.canDecreaseFont,
    required this.canIncreaseFont,
    required this.backgroundColor,
  });

  final AppThemeMode themeMode;
  final VoidCallback onToggleThemeMode;
  final int bookNumber;
  final bool interlinearEnabled;
  final VoidCallback onToggleInterlinear;
  final VoidCallback onMode;
  final VoidCallback onHistory;
  final VoidCallback onLibrary;
  final VoidCallback onDecreaseFont;
  final VoidCallback onIncreaseFont;
  final VoidCallback onCommentary;
  final VoidCallback onMarkup;
  final bool canDecreaseFont;
  final bool canIncreaseFont;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final buttonColor =
        Theme.of(context).iconTheme.color ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87);

    return BottomAppBar(
      color: backgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 320;
          final sidePadding = isCompact ? 4.0 : 8.0;
          final controlGap = isCompact ? 2.0 : 4.0;

          return SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: sidePadding),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'History',
                            onPressed: onHistory,
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints.tightFor(
                              width: isCompact ? 30 : 40,
                              height: isCompact ? 30 : 40,
                            ),
                            icon: Icon(
                              Icons.history_rounded,
                              color: buttonColor,
                              size: isCompact ? 20 : 24,
                            ),
                          ),
                          SizedBox(width: controlGap),
                          _FontScaleButton(
                            onPressed: canDecreaseFont ? onDecreaseFont : null,
                            color: buttonColor,
                            baseSize: 17,
                            sign: '-',
                            signSize: 15,
                            compact: isCompact,
                          ),
                          SizedBox(width: controlGap),
                          _FontScaleButton(
                            onPressed: canIncreaseFont ? onIncreaseFont : null,
                            color: buttonColor,
                            baseSize: 20,
                            sign: '+',
                            signSize: 15,
                            compact: isCompact,
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _BottomIconButton(
                            tooltip: 'Commentary',
                            icon: Icons.menu_book_outlined,
                            color: buttonColor,
                            compact: isCompact,
                            onPressed: onCommentary,
                          ),
                          const SizedBox(width: 2),
                          _LibraryButton(
                            compact: isCompact,
                            onPressed: onLibrary,
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _BottomIconButton(
                            tooltip: 'Mode',
                            icon: Icons.slideshow_rounded,
                            color: buttonColor,
                            compact: isCompact,
                            onPressed: onMode,
                          ),
                          const SizedBox(width: 2),
                          _InterlinearToggleButton(
                            bookNumber: bookNumber,
                            interlinearEnabled: interlinearEnabled,
                            compact: isCompact,
                            baseColor: buttonColor,
                            onToggleInterlinear: onToggleInterlinear,
                          ),
                          const SizedBox(width: 2),
                          _ThemeToggleButton(
                            themeMode: themeMode,
                            compact: isCompact,
                            onToggleThemeMode: onToggleThemeMode,
                          ),
                          const SizedBox(width: 2),
                          _BottomIconButton(
                            tooltip: 'Apply markup',
                            icon: Icons.format_paint_outlined,
                            color: buttonColor,
                            compact: isCompact,
                            onPressed: onMarkup,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
