import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mac_reader_autoscroll_controller.dart';

KeyEventResult handleMacReaderAutoscrollKeyEvent({
  required KeyEvent event,
  required FocusNode readerFocusNode,
  required MacReaderAutoScrollController controller,
  bool suspended = false,
}) {
  if (suspended || !readerFocusNode.hasFocus || _editableControlHasFocus()) {
    return KeyEventResult.ignored;
  }
  if (event is KeyRepeatEvent || event is! KeyDownEvent) {
    return KeyEventResult.ignored;
  }
  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
    controller.increaseStep();
    return KeyEventResult.handled;
  }
  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
    controller.decreaseStep();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

bool _editableControlHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final widget = context.widget;
  final focusedIconButton = widget is IconButton
      ? widget
      : context.findAncestorWidgetOfExactType<IconButton>();
  if (focusedIconButton?.key == const ValueKey('mac-autoscroll-button')) {
    return false;
  }
  return widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null ||
      focusedIconButton != null ||
      context.findAncestorWidgetOfExactType<TextButton>() != null ||
      context.findAncestorWidgetOfExactType<FilledButton>() != null ||
      context.findAncestorWidgetOfExactType<OutlinedButton>() != null ||
      context.findAncestorWidgetOfExactType<Slider>() != null ||
      context.findAncestorWidgetOfExactType<DropdownButton<Object?>>() != null;
}

class MacReaderAutoScrollButton extends StatelessWidget {
  const MacReaderAutoScrollButton({
    super.key,
    required this.controller,
    required this.onPressed,
    required this.onLongPress,
    this.enabled = true,
  });

  final MacReaderAutoScrollController controller;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      return Semantics(
        button: true,
        label: controller.statusLabel,
        hint: 'Click to start or stop. Long press for Mac Autoscroll settings.',
        child: Tooltip(
          message: 'Mac Autoscroll',
          child: GestureDetector(
            onLongPress: enabled ? onLongPress : null,
            child: IconButton(
              key: const ValueKey('mac-autoscroll-button'),
              onPressed: enabled ? onPressed : null,
              icon: const Icon(Icons.swap_vert),
            ),
          ),
        ),
      );
    },
  );
}

class MacReaderAutoscrollStatusOverlay extends StatelessWidget {
  const MacReaderAutoscrollStatusOverlay({
    super.key,
    required this.status,
    required this.foregroundColor,
    required this.backgroundColor,
    this.right = 20,
    this.bottom = 70,
  });

  final String? status;
  final Color foregroundColor;
  final Color backgroundColor;
  final double right;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final value = status;
    if (value == null) return const SizedBox.shrink();
    return Positioned(
      right: right,
      bottom: bottom,
      child: Semantics(
        liveRegion: true,
        label: value,
        child: IgnorePointer(
          child: Material(
            color: foregroundColor.withValues(alpha: .9),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                value,
                key: const ValueKey('mac-autoscroll-status'),
                style: TextStyle(color: backgroundColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<MacAutoscrollPreferences?> showMacAutoscrollSettingsDialog({
  required BuildContext context,
  required MacAutoscrollPreferences initial,
}) => showDialog<MacAutoscrollPreferences>(
  context: context,
  builder: (context) => _MacAutoscrollSettingsDialog(initial: initial),
);

class _MacAutoscrollSettingsDialog extends StatefulWidget {
  const _MacAutoscrollSettingsDialog({required this.initial});
  final MacAutoscrollPreferences initial;

  @override
  State<_MacAutoscrollSettingsDialog> createState() =>
      _MacAutoscrollSettingsDialogState();
}

class _MacAutoscrollSettingsDialogState
    extends State<_MacAutoscrollSettingsDialog> {
  late double _baseSpeed = widget.initial.baseSpeed;
  late int _maximumStep = widget.initial.maximumStep;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Mac Autoscroll'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Base reading speed: ${_baseSpeed.round()} pixels per second'),
          Slider(
            key: const ValueKey('mac-autoscroll-base-speed'),
            value: _baseSpeed,
            min: 6,
            max: 60,
            divisions: 18,
            onChanged: (value) => setState(() => _baseSpeed = value),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: const ValueKey('mac-autoscroll-maximum-step'),
            initialValue: _maximumStep,
            decoration: const InputDecoration(labelText: 'Maximum speed step'),
            items:
                List<int>.generate(
                      defaultMacAutoscrollMaximumStep,
                      (index) => index + 1,
                    )
                    .map(
                      (value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value×'),
                      ),
                    )
                    .toList(growable: false),
            onChanged: (value) {
              if (value != null) setState(() => _maximumStep = value);
            },
          ),
          const SizedBox(height: 16),
          const Text('Arrow keys change speed and direction.'),
          const Text('Up Arrow: one step upward'),
          const Text('Down Arrow: one step downward'),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        key: const ValueKey('mac-autoscroll-cancel'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('mac-autoscroll-save'),
        onPressed: () => Navigator.of(context).pop(
          MacAutoscrollPreferences(
            baseSpeed: _baseSpeed,
            lastNonzeroStep: widget.initial.lastNonzeroStep.clamp(
              -_maximumStep,
              _maximumStep,
            ),
            maximumStep: _maximumStep,
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}
