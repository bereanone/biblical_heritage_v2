import 'package:flutter/material.dart';

import 'presentation_prep/presentation_ui_helpers.dart';

enum ReaderTagFamily { hash, dollar }

class ReaderTagButtons extends StatelessWidget {
  const ReaderTagButtons({
    super.key,
    required this.fontScale,
    required this.activeFamily,
    required this.onStandardTap,
    required this.onDollarTap,
    required this.onRapidTap,
    this.showStandard = true,
    this.showDollar = true,
    this.showRapid = true,
  });

  final double fontScale;
  final ReaderTagFamily? activeFamily;
  final VoidCallback onStandardTap;
  final VoidCallback onDollarTap;
  final VoidCallback onRapidTap;
  final bool showStandard;
  final bool showDollar;
  final bool showRapid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 420;
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final buttonExtent = presentationScaledSize(
      context,
      isWide ? 44 : (compact ? 40 : 42),
      fontScale,
      min: 40,
      max: 52,
    );
    final glyphFontSize = presentationScaledSize(
      context,
      isWide ? 21 : (compact ? 18 : 19),
      fontScale,
      min: 18,
      max: 24,
    );
    final iconSize = presentationScaledSize(
      context,
      isWide ? 21 : (compact ? 18 : 19),
      fontScale,
      min: 18,
      max: 24,
    );
    final rapidColor = theme.colorScheme.primary;
    final activeColor = theme.colorScheme.primary;
    final activeForeground = theme.colorScheme.onPrimary;
    final inactiveForeground = theme.colorScheme.onSurface.withValues(
      alpha: 0.84,
    );
    final inactiveBorder = inactiveForeground.withValues(alpha: 0.18);

    final children = <Widget>[];

    if (showStandard) {
      children.add(
        Tooltip(
          message: '# Tags',
          child: _GlyphButton(
            glyph: '#',
            size: buttonExtent,
            glyphFontSize: glyphFontSize,
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
      );
    }

    if (showDollar) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(width: 8));
      }
      children.add(
        Tooltip(
          message: 'Presentation Setup',
          child: _IconButton(
            icon: Icons.slideshow_outlined,
            size: buttonExtent,
            iconSize: iconSize,
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
      );
    }

    if (showRapid) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(width: 8));
      }
      children.add(
        Tooltip(
          message: '! Rapid tag',
          child: _GlyphButton(
            glyph: '!',
            size: buttonExtent,
            glyphFontSize: glyphFontSize,
            iconColor: theme.colorScheme.onPrimary,
            backgroundColor: rapidColor,
            borderColor: rapidColor,
            onPressed: onRapidTap,
            elevated: true,
          ),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class _GlyphButton extends StatelessWidget {
  const _GlyphButton({
    required this.glyph,
    required this.size,
    required this.glyphFontSize,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onPressed,
    this.elevated = false,
  });

  final String glyph;
  final double size;
  final double glyphFontSize;
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
          width: size,
          height: size,
          child: Center(
            child: Text(
              glyph,
              style: TextStyle(
                fontSize: glyphFontSize,
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

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onPressed,
    this.elevated = false,
  });

  final IconData icon;
  final double size;
  final double iconSize;
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
          width: size,
          height: size,
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }
}
