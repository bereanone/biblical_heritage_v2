import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_mode.dart';

class ViewerBottomBar extends StatelessWidget {
  const ViewerBottomBar({
    super.key,
    required this.themeMode,
    required this.onToggleThemeMode,
    required this.onMode,
    required this.onHistory,
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
  final VoidCallback onMode;
  final VoidCallback onHistory;
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
                          _LibraryStubButton(compact: isCompact),
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

class _LibraryStubButton extends StatelessWidget {
  const _LibraryStubButton({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconColor = const Color(0xFF2E6FD6);
    final textStyle = TextStyle(
      color: iconColor,
      fontWeight: FontWeight.w700,
      fontSize: compact ? 8 : 9,
      height: 1,
    );

    return Tooltip(
      message: 'eLibrary',
      child: Semantics(
        button: true,
        label: 'eLibrary',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('eLibrary not wired yet')),
              );
            },
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: compact ? 38 : 46,
              height: compact ? 38 : 46,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.library_books_outlined,
                    color: iconColor,
                    size: compact ? 18 : 20,
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 1),
                    Text('eLibrary', style: textStyle),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton({
    required this.themeMode,
    required this.compact,
    required this.onToggleThemeMode,
  });

  final AppThemeMode themeMode;
  final bool compact;
  final VoidCallback onToggleThemeMode;

  @override
  Widget build(BuildContext context) {
    final isNight = themeMode == AppThemeMode.night;
    final label = isNight ? 'Sepia' : 'Night';
    final icon = isNight ? Icons.wb_sunny_outlined : Icons.nightlight_round;
    final showLabel = !compact;

    return Tooltip(
      message: 'Switch to $label mode',
      child: Semantics(
        button: true,
        label: 'Switch to $label mode',
        child: Material(
          color: const Color(0xFF8A5A2C),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onToggleThemeMode,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 12,
                vertical: compact ? 6 : 7,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: compact ? 15 : 18, color: Colors.white),
                  if (showLabel) ...[
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.96),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomIconButton extends StatelessWidget {
  const _BottomIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.compact,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: compact ? 30 : 40,
        height: compact ? 30 : 40,
      ),
      icon: Icon(icon, color: color, size: compact ? 20 : 24),
    );
  }
}

class _FontScaleButton extends StatelessWidget {
  const _FontScaleButton({
    required this.onPressed,
    required this.color,
    required this.baseSize,
    required this.sign,
    required this.signSize,
    required this.compact,
  });

  final VoidCallback? onPressed;
  final Color color;
  final double baseSize;
  final String sign;
  final double signSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final effectiveColor = enabled ? color : color.withValues(alpha: 0.35);

    return SizedBox(
      width: compact ? 28 : 34,
      height: compact ? 28 : 34,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'A',
                  textScaler: TextScaler.noScaling,
                  softWrap: false,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: baseSize,
                    fontWeight: FontWeight.w600,
                    color: effectiveColor,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 1),
                Text(
                  sign,
                  textScaler: TextScaler.noScaling,
                  softWrap: false,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: signSize,
                    fontWeight: FontWeight.w700,
                    color: effectiveColor,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
