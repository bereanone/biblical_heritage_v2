import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mac_reader_autoscroll_controller.dart';
import 'reader_tilt_preferences.dart';

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
  if (!controller.isActive) return KeyEventResult.ignored;
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
    builder: (context, _) => Semantics(
      button: true,
      label: controller.statusLabel,
      hint: 'Click to start or stop. Long press for Autoscroll settings.',
      child: Tooltip(
        message: 'Autoscroll',
        child: GestureDetector(
          onLongPress: enabled ? onLongPress : null,
          child: IconButton(
            key: const ValueKey('mac-autoscroll-button'),
            onPressed: enabled ? onPressed : null,
            icon: const Icon(Icons.swap_vert),
          ),
        ),
      ),
    ),
  );
}

class ReaderAutoScrollButton extends StatelessWidget {
  const ReaderAutoScrollButton({
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
    builder: (context, _) => Semantics(
      button: true,
      label: controller.statusLabel,
      hint: 'Tap to start or stop. Long press for Autoscroll settings.',
      child: Tooltip(
        message: 'Autoscroll',
        child: GestureDetector(
          onLongPress: enabled ? onLongPress : null,
          child: IconButton(
            key: const ValueKey('elibrary-auto-scroll'),
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: enabled ? onPressed : null,
            icon: const Icon(Icons.swap_vert_rounded),
          ),
        ),
      ),
    ),
  );
}

class MacReaderAutoscrollStatusOverlay extends StatefulWidget {
  const MacReaderAutoscrollStatusOverlay({
    super.key,
    required this.controller,
    required this.foregroundColor,
    required this.backgroundColor,
    this.right = 20,
    this.bottom = 70,
  });

  final MacReaderAutoScrollController controller;
  final Color foregroundColor;
  final Color backgroundColor;
  final double right;
  final double bottom;

  static const autoHideDuration = Duration(seconds: 7);

  @override
  State<MacReaderAutoscrollStatusOverlay> createState() =>
      _MacReaderAutoscrollStatusOverlayState();
}

class _MacReaderAutoscrollStatusOverlayState
    extends State<MacReaderAutoscrollStatusOverlay> {
  Timer? _hideTimer;
  bool _autoHideVisible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(MacReaderAutoscrollStatusOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChange);
    _hideTimer?.cancel();
    _autoHideVisible = false;
    widget.controller.addListener(_handleControllerChange);
  }

  void _handleControllerChange() {
    _hideTimer?.cancel();
    if (widget.controller.statusBannerMode ==
        ReaderTiltStatusBannerMode.autoHide) {
      setState(() => _autoHideVisible = true);
      _hideTimer = Timer(MacReaderAutoscrollStatusOverlay.autoHideDuration, () {
        if (mounted) setState(() => _autoHideVisible = false);
      });
    } else {
      setState(() => _autoHideVisible = false);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_handleControllerChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final visible = switch (controller.statusBannerMode) {
      ReaderTiltStatusBannerMode.alwaysVisible => controller.isActive,
      ReaderTiltStatusBannerMode.autoHide => _autoHideVisible,
      ReaderTiltStatusBannerMode.alwaysHidden => false,
    };
    if (!visible) return const SizedBox.shrink();
    final value = controller.statusLabel;
    return Positioned(
      right: widget.right,
      bottom: widget.bottom,
      child: Semantics(
        liveRegion: true,
        label: value,
        child: IgnorePointer(
          child: Material(
            color: widget.foregroundColor.withValues(alpha: .9),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                value,
                key: const ValueKey('mac-autoscroll-status'),
                style: TextStyle(color: widget.backgroundColor),
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

Future<MacAutoscrollPreferences?> showReaderAutoscrollSettingsDialog({
  required BuildContext context,
  required MacAutoscrollPreferences initial,
}) => showDialog<MacAutoscrollPreferences>(
  context: context,
  builder: (context) => _MacAutoscrollSettingsDialog(
    initial: initial,
    title: 'Autoscroll',
    showKeyboardHelp: false,
    showStatusBanner: false,
  ),
);

class _MacAutoscrollSettingsDialog extends StatefulWidget {
  const _MacAutoscrollSettingsDialog({
    required this.initial,
    this.title = 'Mac Autoscroll',
    this.showKeyboardHelp = true,
    this.showStatusBanner = true,
  });
  final MacAutoscrollPreferences initial;
  final String title;
  final bool showKeyboardHelp;
  final bool showStatusBanner;

  @override
  State<_MacAutoscrollSettingsDialog> createState() =>
      _MacAutoscrollSettingsDialogState();
}

class _MacAutoscrollSettingsDialogState
    extends State<_MacAutoscrollSettingsDialog> {
  late double _baseSpeed = widget.initial.baseSpeed;
  late int _maximumStep = widget.initial.maximumStep;
  late ReaderTiltStatusBannerMode _statusBannerMode =
      widget.initial.statusBannerMode;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Reading speed: ${_baseSpeed.round()} pixels per second'),
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
              decoration: const InputDecoration(
                labelText: 'Maximum speed step',
              ),
              items: macAutoscrollSpeedSteps
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
            if (widget.showKeyboardHelp) ...[
              const Text('Arrow keys change speed and direction.'),
              const Text('Up Arrow: one step upward'),
              const Text('Down Arrow: one step downward'),
            ],
            if (widget.showStatusBanner) ...[
              const SizedBox(height: 16),
              const Text('Status Banner'),
              RadioGroup<ReaderTiltStatusBannerMode>(
                groupValue: _statusBannerMode,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _statusBannerMode = value);
                  }
                },
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    RadioListTile<ReaderTiltStatusBannerMode>(
                      title: Text('Always Visible'),
                      value: ReaderTiltStatusBannerMode.alwaysVisible,
                    ),
                    RadioListTile<ReaderTiltStatusBannerMode>(
                      title: Text('Auto-hide after 7 seconds'),
                      value: ReaderTiltStatusBannerMode.autoHide,
                    ),
                    RadioListTile<ReaderTiltStatusBannerMode>(
                      title: Text('Always Hidden'),
                      value: ReaderTiltStatusBannerMode.alwaysHidden,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
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
            lastNonzeroStep: normalizeMacAutoscrollRememberedStep(
              widget.initial.lastNonzeroStep,
              _maximumStep,
            ),
            maximumStep: _maximumStep,
            statusBannerMode: _statusBannerMode,
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}
