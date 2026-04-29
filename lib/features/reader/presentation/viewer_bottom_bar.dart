import 'package:flutter/material.dart';

class ViewerBottomBar extends StatelessWidget {
  const ViewerBottomBar({
    super.key,
    required this.onHistory,
    required this.onDecreaseFont,
    required this.onIncreaseFont,
    required this.onMode,
    required this.onMarkup,
    required this.canDecreaseFont,
    required this.canIncreaseFont,
    required this.backgroundColor,
  });

  final VoidCallback onHistory;
  final VoidCallback onDecreaseFont;
  final VoidCallback onIncreaseFont;
  final VoidCallback onMode;
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
                    _BottomIconButton(
                      tooltip: 'Reader tools',
                      icon: Icons.menu_book_rounded,
                      color: buttonColor,
                      compact: isCompact,
                      onPressed: () {},
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _BottomDisplayButton(
                            color: buttonColor,
                            compact: isCompact,
                            onPressed: onMode,
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

class _BottomDisplayButton extends StatelessWidget {
  const _BottomDisplayButton({
    required this.color,
    required this.compact,
    required this.onPressed,
  });

  final Color color;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Mode',
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: compact ? 30 : 40,
        height: compact ? 30 : 40,
      ),
      icon: Icon(
        Icons.slideshow_rounded,
        color: color,
        size: compact ? 20 : 24,
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
      icon: Icon(
        icon,
        color: color,
        size: compact ? 20 : 24,
      ),
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
