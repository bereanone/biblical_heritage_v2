part of 'viewer_bottom_bar.dart';

class _LibraryButton extends StatelessWidget {
  const _LibraryButton({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback onPressed;

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
            onTap: onPressed,
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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

class _InterlinearToggleButton extends StatelessWidget {
  const _InterlinearToggleButton({
    required this.bookNumber,
    required this.interlinearEnabled,
    required this.compact,
    required this.baseColor,
    required this.onToggleInterlinear,
  });

  final int bookNumber;
  final bool interlinearEnabled;
  final bool compact;
  final Color baseColor;
  final VoidCallback onToggleInterlinear;

  @override
  Widget build(BuildContext context) {
    final isOldTestament = bookNumber >= 1 && bookNumber <= 39;
    final glyph = isOldTestament ? 'א' : 'Α';
    final glyphColor = interlinearEnabled ? const Color(0xFFD00000) : baseColor;
    final size = compact ? 24.0 : 28.0;

    return Tooltip(
      message: 'Toggle Interlinear Mode',
      child: Semantics(
        button: true,
        label: 'Toggle Interlinear Mode',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggleInterlinear,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: compact ? 34 : 40,
              height: compact ? 34 : 40,
              child: Center(
                child: Text(
                  glyph,
                  style: TextStyle(
                    color: glyphColor,
                    fontWeight: FontWeight.w800,
                    fontSize: size,
                    height: 1,
                  ),
                ),
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
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(
          width: compact ? 34 : 40,
          height: compact ? 34 : 40,
        ),
        icon: Icon(icon, color: color, size: compact ? 18 : 22),
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
    return IconButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: compact ? 28 : 36,
        height: compact ? 28 : 36,
      ),
      icon: Text(
        sign,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: signSize,
          height: 1,
        ),
      ),
    );
  }
}
