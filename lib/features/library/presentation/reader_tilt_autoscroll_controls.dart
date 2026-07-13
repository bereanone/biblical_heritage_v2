import 'package:flutter/material.dart';

import 'reader_tilt_autoscroll_controller.dart';
import 'reader_tilt_preferences.dart';

class ReaderTiltAutoScrollIconButton extends StatelessWidget {
  const ReaderTiltAutoScrollIconButton({
    super.key,
    required this.controller,
    required this.onPressed,
    this.enabled = true,
    this.compact = true,
    this.onLongPress,
  });

  final ReaderTiltAutoScrollController controller;
  final VoidCallback onPressed;
  final bool enabled;
  final bool compact;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = controller.isActive;
    return Semantics(
      button: true,
      label: 'Tilt Auto-scroll',
      hint: 'Tap to start or stop. Long press for settings.',
      toggled: active,
      child: Tooltip(
        message: 'Tilt Auto-scroll',
        child: Material(
          color: active ? colors.primaryContainer : Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onPressed : null,
            onLongPress: enabled ? onLongPress : null,
            child: SizedBox(
              width: compact ? 36 : 44,
              height: compact ? 36 : 44,
              child: Icon(
                Icons.swap_vert_rounded,
                size: compact ? 23 : 26,
                color: enabled
                    ? active
                          ? colors.onPrimaryContainer
                          : colors.onSurface
                    : colors.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showReaderTiltSettingsSheet(
  BuildContext context, {
  required ReaderTiltPreferences preferences,
  required bool includeChapterTilt,
  required ValueChanged<ReaderTiltPreferences> onChanged,
  required VoidCallback onRecalibrate,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) {
    var current = preferences;
    return StatefulBuilder(
      builder: (context, setSheetState) {
        void update(ReaderTiltPreferences next) {
          setSheetState(() => current = next);
          onChanged(next);
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tilt Auto-scroll Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Tip forward to scroll down'),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Tip forward to scroll up'),
                      ),
                    ],
                    selected: {current.reverseVerticalDirection},
                    onSelectionChanged: (selection) => update(
                      current.copyWith(
                        reverseVerticalDirection: selection.first,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Neutral zone • ${(current.neutralZoneFraction * 100).round()}%',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Slider(
                    value: current.neutralZoneFraction,
                    min: ReaderTiltPreferences.minimumNeutralZoneFraction,
                    max: ReaderTiltPreferences.maximumNeutralZoneFraction,
                    divisions: 8,
                    semanticFormatterCallback: (value) =>
                        '${(value * 100).round()} percent neutral zone',
                    onChanged: (value) =>
                        update(current.copyWith(neutralZoneFraction: value)),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text('More sensitive'), Text('Less sensitive')],
                  ),
                  const Text(
                    'A larger neutral zone helps prevent accidental scrolling.',
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Scroll speed • ${(current.speedMultiplier * 100).round()}%',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Slider(
                    value: current.speedMultiplier,
                    min: ReaderTiltPreferences.minimumSpeedMultiplier,
                    max: ReaderTiltPreferences.maximumSpeedMultiplier,
                    divisions: 15,
                    semanticFormatterCallback: (value) =>
                        '${(value * 100).round()} percent scroll speed',
                    onChanged: (value) =>
                        update(current.copyWith(speedMultiplier: value)),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text('Slower'), Text('Faster')],
                  ),
                  if (includeChapterTilt) ...[
                    const Divider(height: 32),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tilt Sideways to Change Chapter'),
                      value: current.horizontalChapterTiltEnabled,
                      onChanged: (value) => update(
                        current.copyWith(horizontalChapterTiltEnabled: value),
                      ),
                    ),
                    if (current.horizontalChapterTiltEnabled) ...[
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Right = Next, Left = Previous'),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Right = Previous, Left = Next'),
                          ),
                        ],
                        selected: {current.reverseHorizontalDirection},
                        onSelectionChanged: (selection) => update(
                          current.copyWith(
                            reverseHorizontalDirection: selection.first,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sideways sensitivity',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Slider(
                        value: current.horizontalSensitivity,
                        min: 0,
                        max: 1,
                        divisions: 6,
                        onChanged: (value) => update(
                          current.copyWith(horizontalSensitivity: value),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: onRecalibrate,
                    icon: const Icon(Icons.center_focus_strong_outlined),
                    label: const Text('Set Current Angle as Neutral'),
                  ),
                  TextButton(
                    onPressed: () => update(
                      includeChapterTilt
                          ? ReaderTiltPreferences.defaults
                          : current.copyWith(
                              reverseVerticalDirection: false,
                              neutralZoneFraction: 0.05,
                              speedMultiplier: 1.0,
                            ),
                    ),
                    child: const Text('Restore Defaults'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  },
);

class ReaderTiltAutoScrollActiveIndicator extends StatelessWidget {
  const ReaderTiltAutoScrollActiveIndicator({
    super.key,
    required this.controller,
  });

  final ReaderTiltAutoScrollController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.isActive) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final calibrating =
        controller.state == ReaderTiltAutoScrollState.calibrating;
    final direction = controller.speedPixelsPerSecond < 0
        ? '↑ Backward'
        : controller.speedPixelsPerSecond > 0
        ? '↓ Forward'
        : '• Still';
    return SafeArea(
      minimum: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: theme.colorScheme.primaryContainer,
        elevation: 3,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                calibrating
                    ? 'Tilt Auto-scroll • Calibrating…'
                    : 'Tilt Auto-scroll • $direction • ${controller.speedPercent}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                tooltip: 'Recalibrate Tilt Auto-scroll',
                onPressed: controller.recalibrate,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.center_focus_strong_outlined, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
