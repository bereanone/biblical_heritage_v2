import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_mode.dart';

class ViewerThemePickerButton extends StatelessWidget {
  const ViewerThemePickerButton({
    super.key,
    required this.themeMode,
    required this.onSelected,
    required this.color,
    required this.compact,
  });

  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode> onSelected;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppThemeMode>(
      tooltip: 'Choose theme',
      initialValue: themeMode,
      onSelected: onSelected,
      padding: EdgeInsets.zero,
      itemBuilder: (context) => const [
        PopupMenuItem<AppThemeMode>(
          value: AppThemeMode.sepia,
          child: Text('Sepia'),
        ),
        PopupMenuItem<AppThemeMode>(
          value: AppThemeMode.night,
          child: Text('Night'),
        ),
      ],
      child: SizedBox(
        width: compact ? 30 : 40,
        height: compact ? 30 : 40,
        child: Center(
          child: Icon(
            Icons.format_paint_outlined,
            color: color,
            size: compact ? 20 : 24,
          ),
        ),
      ),
    );
  }
}
