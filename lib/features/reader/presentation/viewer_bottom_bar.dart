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
          final controlGap = isCompact ? 4.0 : 6.0;
          final libraryAlignmentX = isCompact ? 0.2 : 0.42;

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
                              width: isCompact ? 36 : 44,
                              height: isCompact ? 36 : 44,
                            ),
                            icon: Icon(
                              Icons.history_rounded,
                              color: buttonColor,
                              size: isCompact ? 22 : 26,
                            ),
                          ),
                          SizedBox(width: controlGap),
                          _FontScaleButton(
                            onPressed: canDecreaseFont ? onDecreaseFont : null,
                            color: buttonColor,
                            baseSize: isCompact ? 14 : 15,
                            sign: 'A-',
                            signSize: isCompact ? 10 : 11,
                            compact: isCompact,
                          ),
                          SizedBox(width: controlGap),
                          _FontScaleButton(
                            onPressed: canIncreaseFont ? onIncreaseFont : null,
                            color: buttonColor,
                            baseSize: isCompact ? 19 : 23,
                            sign: 'A+',
                            signSize: isCompact ? 11 : 12,
                            compact: isCompact,
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: _BottomIconButton(
                        tooltip: 'Commentary',
                        icon: Icons.menu_book_outlined,
                        color: buttonColor,
                        compact: isCompact,
                        onPressed: onCommentary,
                      ),
                    ),
                    Align(
                      alignment: Alignment(libraryAlignmentX, 0),
                      child: _LibraryButton(
                        compact: isCompact,
                        onPressed: onLibrary,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                            tooltip: 'Mode',
                            icon: Icons.settings_rounded,
                            color: buttonColor,
                            compact: isCompact,
                            onPressed: onMode,
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
