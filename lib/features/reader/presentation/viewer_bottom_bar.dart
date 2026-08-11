import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_mode.dart';
import '../../library/presentation/mac_reader_autoscroll_controller.dart';
import '../../library/presentation/mac_reader_autoscroll_controls.dart';
import '../../library/presentation/reader_tilt_autoscroll_controller.dart';
import '../../library/presentation/reader_tilt_autoscroll_controls.dart';

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
    required this.tiltAutoScrollController,
    required this.onToggleTiltAutoScroll,
    required this.onOpenTiltAutoScrollSettings,
    required this.onCommentary,
    required this.canDecreaseFont,
    required this.canIncreaseFont,
    required this.backgroundColor,
    this.macAutoScrollController,
    this.onToggleMacAutoScroll,
    this.onOpenMacAutoScrollSettings,
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
  final ReaderTiltAutoScrollController tiltAutoScrollController;
  final VoidCallback onToggleTiltAutoScroll;
  final VoidCallback onOpenTiltAutoScrollSettings;
  final VoidCallback onCommentary;
  final bool canDecreaseFont;
  final bool canIncreaseFont;
  final Color backgroundColor;
  final MacReaderAutoScrollController? macAutoScrollController;
  final VoidCallback? onToggleMacAutoScroll;
  final VoidCallback? onOpenMacAutoScrollSettings;

  Widget _autoScrollButton({bool compact = false}) {
    final macController = macAutoScrollController;
    if (macController != null) {
      if (tiltAutoScrollController.motionSource.isSupported) {
        return ReaderTiltAutoScrollIconButton(
          controller: tiltAutoScrollController,
          onPressed: onToggleTiltAutoScroll,
          onLongPress: onOpenTiltAutoScrollSettings,
          enabled: !interlinearEnabled,
          compact: compact,
        );
      }
      return MacReaderAutoScrollButton(
        controller: macController,
        onPressed: onToggleMacAutoScroll!,
        onLongPress: onOpenMacAutoScrollSettings!,
        enabled: !interlinearEnabled,
      );
    }
    return ReaderTiltAutoScrollIconButton(
      controller: tiltAutoScrollController,
      onPressed: onToggleTiltAutoScroll,
      onLongPress: onOpenTiltAutoScrollSettings,
      enabled: tiltAutoScrollController.motionSource.isSupported,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttonColor =
        Theme.of(context).iconTheme.color ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87);

    return BottomAppBar(
      color: backgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700;
          final isCompact = constraints.maxWidth < 440;
          final sidePadding = isCompact ? 4.0 : 8.0;

          if (!isWide) {
            if (isCompact) {
              return SafeArea(
                top: false,
                child: SizedBox(
                  height: 56,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: sidePadding),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'History',
                          onPressed: onHistory,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
                          icon: Icon(
                            Icons.history_rounded,
                            color: buttonColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 2),
                        _FontScaleButton(
                          onPressed: canDecreaseFont ? onDecreaseFont : null,
                          color: buttonColor,
                          baseSize: 14,
                          sign: 'A-',
                          signSize: 10,
                          compact: true,
                        ),
                        const SizedBox(width: 2),
                        _FontScaleButton(
                          onPressed: canIncreaseFont ? onIncreaseFont : null,
                          color: buttonColor,
                          baseSize: 19,
                          sign: 'A+',
                          signSize: 11,
                          compact: true,
                        ),
                        const SizedBox(width: 2),
                        _autoScrollButton(),
                        const SizedBox(width: 8),
                        _BottomIconButton(
                          tooltip: 'Commentary',
                          icon: Icons.menu_book_outlined,
                          color: buttonColor,
                          compact: true,
                          onPressed: onCommentary,
                        ),
                        const SizedBox(width: 2),
                        _LibraryButton(compact: true, onPressed: onLibrary),
                        const SizedBox(width: 2),
                        _InterlinearToggleButton(
                          bookNumber: bookNumber,
                          interlinearEnabled: interlinearEnabled,
                          compact: true,
                          baseColor: buttonColor,
                          onToggleInterlinear: onToggleInterlinear,
                        ),
                        const SizedBox(width: 2),
                        _ThemeToggleButton(
                          themeMode: themeMode,
                          compact: true,
                          onToggleThemeMode: onToggleThemeMode,
                        ),
                        const SizedBox(width: 2),
                        _BottomIconButton(
                          tooltip: 'Mode',
                          icon: Icons.settings_rounded,
                          color: buttonColor,
                          compact: true,
                          onPressed: onMode,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            // Below this width the complete set of minimum-size hit targets
            // cannot fit without compression. Keep every action full-size and
            // let the toolbar scroll horizontally instead.
            if (constraints.maxWidth < 440) {
              return SafeArea(
                top: false,
                child: SizedBox(
                  height: 56,
                  child: Padding(
                    padding: EdgeInsets.only(left: sidePadding),
                    child: Row(
                      children: [
                        // Priority controls stay fixed and fully on-screen.
                        // Commentary and eLibrary are core navigation and
                        // must always be visible here, never inside the
                        // scrollable low-priority section below (which can
                        // render effectively empty if the available width is
                        // tight, hiding them entirely).
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'History',
                              onPressed: onHistory,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 36,
                                height: 36,
                              ),
                              icon: Icon(
                                Icons.history_rounded,
                                color: buttonColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 2),
                            _FontScaleButton(
                              onPressed: canDecreaseFont
                                  ? onDecreaseFont
                                  : null,
                              color: buttonColor,
                              baseSize: 14,
                              sign: 'A-',
                              signSize: 10,
                              compact: true,
                            ),
                            const SizedBox(width: 2),
                            _FontScaleButton(
                              onPressed: canIncreaseFont
                                  ? onIncreaseFont
                                  : null,
                              color: buttonColor,
                              baseSize: 19,
                              sign: 'A+',
                              signSize: 11,
                              compact: true,
                            ),
                            const SizedBox(width: 2),
                            _autoScrollButton(),
                            const SizedBox(width: 8),
                            _BottomIconButton(
                              tooltip: 'Commentary',
                              icon: Icons.menu_book_outlined,
                              color: buttonColor,
                              compact: true,
                              onPressed: onCommentary,
                            ),
                            const SizedBox(width: 2),
                            _LibraryButton(compact: true, onPressed: onLibrary),
                            const SizedBox(width: 6),
                          ],
                        ),
                        // Lower-priority controls scroll independently; moving
                        // them can never move Tilt Auto-scroll, Commentary,
                        // or eLibrary off-screen.
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.only(right: sidePadding),
                            child: Row(
                              children: [
                                _InterlinearToggleButton(
                                  bookNumber: bookNumber,
                                  interlinearEnabled: interlinearEnabled,
                                  compact: true,
                                  baseColor: buttonColor,
                                  onToggleInterlinear: onToggleInterlinear,
                                ),
                                const SizedBox(width: 2),
                                _ThemeToggleButton(
                                  themeMode: themeMode,
                                  compact: true,
                                  onToggleThemeMode: onToggleThemeMode,
                                ),
                                const SizedBox(width: 2),
                                _BottomIconButton(
                                  tooltip: 'Mode',
                                  icon: Icons.settings_rounded,
                                  color: buttonColor,
                                  compact: true,
                                  onPressed: onMode,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            // Phone layout: Row with two equal Expanded clusters so
            // Commentary stays geometrically centered regardless of cluster widths.
            // All buttons use compact sizing; theme and eLibrary are icon-only.
            return SafeArea(
              top: false,
              child: SizedBox(
                height: 56,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: sidePadding),
                  child: Row(
                    children: [
                      // Left cluster
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            IconButton(
                              tooltip: 'History',
                              onPressed: onHistory,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 36,
                                height: 36,
                              ),
                              icon: Icon(
                                Icons.history_rounded,
                                color: buttonColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 2),
                            _FontScaleButton(
                              onPressed: canDecreaseFont
                                  ? onDecreaseFont
                                  : null,
                              color: buttonColor,
                              baseSize: 14,
                              sign: 'A-',
                              signSize: 10,
                              compact: true,
                            ),
                            const SizedBox(width: 2),
                            _FontScaleButton(
                              onPressed: canIncreaseFont
                                  ? onIncreaseFont
                                  : null,
                              color: buttonColor,
                              baseSize: 19,
                              sign: 'A+',
                              signSize: 11,
                              compact: true,
                            ),
                            const SizedBox(width: 2),
                            _autoScrollButton(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Commentary — permanently centered between the two Expanded clusters
                      _BottomIconButton(
                        tooltip: 'Commentary',
                        icon: Icons.menu_book_outlined,
                        color: buttonColor,
                        compact: true,
                        onPressed: onCommentary,
                      ),
                      // Right cluster
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _LibraryButton(compact: true, onPressed: onLibrary),
                            const SizedBox(width: 2),
                            _InterlinearToggleButton(
                              bookNumber: bookNumber,
                              interlinearEnabled: interlinearEnabled,
                              compact: true,
                              baseColor: buttonColor,
                              onToggleInterlinear: onToggleInterlinear,
                            ),
                            const SizedBox(width: 2),
                            _ThemeToggleButton(
                              themeMode: themeMode,
                              compact: true,
                              onToggleThemeMode: onToggleThemeMode,
                            ),
                            const SizedBox(width: 2),
                            _BottomIconButton(
                              tooltip: 'Mode',
                              icon: Icons.settings_rounded,
                              color: buttonColor,
                              compact: true,
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
          }

          // Wide layout (iPad / macOS): Stack/Positioned with full-size buttons.
          final controlGap = isCompact ? 4.0 : 6.0;
          const libraryAlignmentX = 0.42;

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
                          SizedBox(width: controlGap),
                          _autoScrollButton(compact: isCompact),
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
                      alignment: const Alignment(libraryAlignmentX, 0),
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
