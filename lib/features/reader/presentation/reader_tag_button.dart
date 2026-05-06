import 'package:flutter/material.dart';

enum ReaderTagFamily { hash, dollar }

class ReaderTagButtons extends StatelessWidget {
  const ReaderTagButtons({
    super.key,
    required this.activeFamily,
    required this.onStandardTap,
    required this.onDollarTap,
    required this.onRapidTap,
  });

  final ReaderTagFamily? activeFamily;
  final VoidCallback onStandardTap;
  final VoidCallback onDollarTap;
  final VoidCallback onRapidTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rapidColor = theme.colorScheme.primary;
    final activeColor = theme.colorScheme.primary;
    final activeForeground = theme.colorScheme.onPrimary;
    final inactiveForeground = theme.colorScheme.onSurface.withValues(
      alpha: 0.84,
    );
    final inactiveBorder = inactiveForeground.withValues(alpha: 0.18);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: '# Tags',
          child: _GlyphButton(
            glyph: '#',
            iconColor: activeFamily == ReaderTagFamily.hash
                ? activeForeground
                : inactiveForeground,
            backgroundColor: activeFamily == ReaderTagFamily.hash
                ? activeColor
                : Colors.transparent,
            borderColor: activeFamily == ReaderTagFamily.hash
                ? activeColor
                : inactiveBorder,
            onPressed: onStandardTap,
            elevated: activeFamily == ReaderTagFamily.hash,
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: r'$ Tags',
          child: _GlyphButton(
            glyph: r'$',
            iconColor: activeFamily == ReaderTagFamily.dollar
                ? activeForeground
                : inactiveForeground,
            backgroundColor: activeFamily == ReaderTagFamily.dollar
                ? activeColor
                : Colors.transparent,
            borderColor: activeFamily == ReaderTagFamily.dollar
                ? activeColor
                : inactiveBorder,
            onPressed: onDollarTap,
            elevated: activeFamily == ReaderTagFamily.dollar,
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: '! Rapid tag',
          child: _GlyphButton(
            glyph: '!',
            iconColor: theme.colorScheme.onPrimary,
            backgroundColor: rapidColor,
            borderColor: rapidColor,
            onPressed: onRapidTap,
            elevated: true,
          ),
        ),
      ],
    );
  }
}

class _GlyphButton extends StatelessWidget {
  const _GlyphButton({
    required this.glyph,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onPressed,
    this.elevated = false,
  });

  final String glyph;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onPressed;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final shadowColor = Theme.of(
      context,
    ).colorScheme.primary.withValues(alpha: 0.18);

    return Material(
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor),
      ),
      elevation: elevated ? 2 : 0,
      shadowColor: shadowColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: Text(
              glyph,
              style: TextStyle(
                fontSize: glyph == '!' ? 22 : 20,
                fontWeight: FontWeight.w900,
                height: 1,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
