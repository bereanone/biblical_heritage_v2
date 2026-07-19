part of 'library_book_reader_screen.dart';

class _ToolbarPillButton extends StatelessWidget {
  const _ToolbarPillButton({
    required this.isNightMode,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool isNightMode;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = _readerTextColor(theme, isNightMode);
    final background = _readerSurfaceHighColor(theme, isNightMode);
    final border = _readerBorderColor(theme, isNightMode);
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: libraryControlTextStyle(
          context,
          theme.textTheme.labelLarge,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
      style: FilledButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        disabledForegroundColor: foreground.withValues(alpha: 0.45),
        disabledBackgroundColor: background.withValues(alpha: 0.45),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(0, 36),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: border),
      ),
    );
  }
}

class _ZoomCluster extends StatelessWidget {
  const _ZoomCluster({
    super.key,
    required this.isNightMode,
    required this.valueLabel,
    required this.onZoomOut,
    required this.onZoomIn,
  });

  final bool isNightMode;
  final String valueLabel;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = _readerTextColor(theme, isNightMode);
    final background = _readerSurfaceHighColor(theme, isNightMode);
    final border = _readerBorderColor(theme, isNightMode);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onZoomOut,
              icon: const Icon(Icons.zoom_out),
              tooltip: 'Zoom out',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              color: foreground,
            ),
            Text(
              valueLabel,
              style: libraryControlTextStyle(
                context,
                theme.textTheme.labelLarge,
                fontWeight: FontWeight.w800,
                color: foreground,
              ),
            ),
            IconButton(
              onPressed: onZoomIn,
              icon: const Icon(Icons.zoom_in),
              tooltip: 'Zoom in',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              color: foreground,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavCluster extends StatelessWidget {
  const _NavCluster({
    required this.isNightMode,
    required this.canGoFirst,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.canGoLast,
    required this.onGoFirst,
    required this.onGoPrevious,
    required this.onGoNext,
    required this.onGoLast,
  });

  final bool isNightMode;
  final bool canGoFirst;
  final bool canGoPrevious;
  final bool canGoNext;
  final bool canGoLast;
  final VoidCallback onGoFirst;
  final VoidCallback onGoPrevious;
  final VoidCallback onGoNext;
  final VoidCallback onGoLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = _readerSurfaceHighColor(theme, isNightMode);
    final border = _readerBorderColor(theme, isNightMode);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavIconButton(
            isNightMode: isNightMode,
            icon: Icons.keyboard_double_arrow_left,
            onPressed: canGoFirst ? onGoFirst : null,
            tooltip: 'Previous section heading',
          ),
          _NavIconButton(
            isNightMode: isNightMode,
            icon: Icons.chevron_left,
            onPressed: canGoPrevious ? onGoPrevious : null,
            tooltip: 'Page up',
          ),
          _NavIconButton(
            isNightMode: isNightMode,
            icon: Icons.chevron_right,
            onPressed: canGoNext ? onGoNext : null,
            tooltip: 'Page down',
          ),
          _NavIconButton(
            isNightMode: isNightMode,
            icon: Icons.keyboard_double_arrow_right,
            onPressed: canGoLast ? onGoLast : null,
            tooltip: 'Next section heading',
          ),
        ],
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.isNightMode,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final bool isNightMode;
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = _readerTextColor(theme, isNightMode);
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      style: IconButton.styleFrom(
        foregroundColor: foreground,
        disabledForegroundColor: foreground.withValues(alpha: 0.35),
      ),
    );
  }
}
