import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_mode.dart';
import 'viewer_presentation_settings.dart';

Future<void> showViewerModePopup(
  BuildContext context, {
  required AppThemeMode themeMode,
  required ValueChanged<AppThemeMode> onThemeChanged,
  required VoidCallback onOpenBibleMemory,
  required bool interlinearEnabled,
  required ValueChanged<bool> onInterlinearChanged,
  required VoidCallback onOpenInterlinearSettings,
  required VoidCallback onOpenColorSetup,
  required PresentationAspectRatioPreset presentationAspectRatio,
  required ValueChanged<PresentationAspectRatioPreset>
      onPresentationAspectRatioChanged,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      var currentPresentationAspectRatio = presentationAspectRatio;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: StatefulBuilder(
            builder: (context, setStateDialog) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ModeRow(
                      title: 'Bible Memory',
                      subtitle: 'Open',
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        onOpenBibleMemory();
                      },
                    ),
                    Divider(
                      height: 8,
                      color: theme.dividerColor.withValues(alpha: 0.55),
                    ),
                    _ModeRow(
                      title: 'Interlinear Mode',
                      subtitle: interlinearEnabled ? 'On' : 'Off',
                      titleColor: interlinearEnabled
                          ? const Color(0xFFD00000)
                          : theme.colorScheme.onSurface,
                      titleFontSizeDelta: interlinearEnabled ? 2 : 0,
                      trailing: IconButton(
                        tooltip: 'Interlinear Settings',
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          onOpenInterlinearSettings();
                        },
                        icon: const Icon(Icons.settings),
                      ),
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        onInterlinearChanged(!interlinearEnabled);
                      },
                    ),
                    Divider(
                      height: 8,
                      color: theme.dividerColor.withValues(alpha: 0.55),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Theme',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _themeLabel(themeMode),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                        PopupMenuButton<AppThemeMode>(
                          tooltip: 'Choose theme',
                          initialValue: themeMode,
                          onSelected: (nextTheme) {
                            Navigator.of(dialogContext).pop();
                            onThemeChanged(nextTheme);
                          },
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
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.dividerColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _themeLabel(themeMode),
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Divider(
                      height: 8,
                      color: theme.dividerColor.withValues(alpha: 0.55),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Presentation Ratio',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  currentPresentationAspectRatio.label,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                        PopupMenuButton<PresentationAspectRatioPreset>(
                          tooltip: 'Choose presentation ratio',
                          initialValue: currentPresentationAspectRatio,
                          onSelected: (preset) {
                            setStateDialog(
                              () => currentPresentationAspectRatio = preset,
                            );
                            onPresentationAspectRatioChanged(preset);
                          },
                          itemBuilder: (context) =>
                              PresentationAspectRatioPreset.values
                                  .map(
                                    (preset) => PopupMenuItem<
                                      PresentationAspectRatioPreset
                                    >(
                                      value: preset,
                                      child: Text(preset.label),
                                    ),
                                  )
                                  .toList(growable: false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.dividerColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  currentPresentationAspectRatio.label,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Divider(
                      height: 8,
                      color: theme.dividerColor.withValues(alpha: 0.55),
                    ),
                    _ModeRow(
                      title: 'Color Setup',
                      subtitle: 'Highlight groups',
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        onOpenColorSetup();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.titleColor,
    this.titleFontSizeDelta = 0,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? titleColor;
  final double titleFontSizeDelta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize:
                          (theme.textTheme.titleMedium?.fontSize ?? 16) +
                          titleFontSizeDelta,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
        trailing ?? const Icon(Icons.chevron_right),
      ],
    );
  }
}

String _themeLabel(AppThemeMode themeMode) {
  switch (themeMode) {
    case AppThemeMode.sepia:
      return 'Sepia';
    case AppThemeMode.night:
      return 'Night';
  }
}
