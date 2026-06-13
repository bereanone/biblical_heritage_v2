part of 'viewer_bottom_bar.dart';

class _LibraryButton extends StatelessWidget {
  const _LibraryButton({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final iconColor = const Color(0xFF2E6FD6);
    // Show the text label only on wide screens (iPad / macOS).
    final showLabel =
        !compact && MediaQuery.sizeOf(context).width >= 700;

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
              width: compact ? 38 : (showLabel ? 58 : 44),
              height: compact ? 38 : (showLabel ? 50 : 44),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_library,
                    color: iconColor,
                    size: compact ? 20 : 22,
                  ),
                  if (showLabel) ...[
                    const SizedBox(height: 1),
                    Text(
                      'eLibrary',
                      style: TextStyle(
                        color: iconColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        height: 1,
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
    // Show the text label only on wide screens (iPad / macOS).
    final showLabel =
        !compact && MediaQuery.sizeOf(context).width >= 700;

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
    final glyph = isOldTestament ? 'א' : 'α';
    final glyphColor = interlinearEnabled ? const Color(0xFFD00000) : baseColor;

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
              width: compact ? 38 : 44,
              height: compact ? 38 : 44,
              child: Center(
                child: Text(
                  glyph,
                  style: TextStyle(
                    color: glyphColor,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 26.0 : 30.0,
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
          width: compact ? 38 : 44,
          height: compact ? 38 : 44,
        ),
        icon: Icon(icon, color: color, size: compact ? 20 : 24),
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
        width: compact ? 36 : 44,
        height: compact ? 36 : 44,
      ),
      icon: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: sign.substring(0, 1),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: baseSize,
                height: 1,
              ),
            ),
            TextSpan(
              text: sign.substring(1),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: signSize,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
