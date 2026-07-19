import 'dart:async';

import 'package:flutter/gestures.dart';
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
    this.interactionGeneration = 0,
  });

  final ReaderTiltAutoScrollController controller;
  final VoidCallback onPressed;
  final bool enabled;
  final bool compact;
  final VoidCallback? onLongPress;
  final int interactionGeneration;

  static const longPressDuration = Duration(milliseconds: 900);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
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
              child: _ReaderDeliberateHoldGesture(
                enabled: enabled,
                active: active,
                interactionGeneration: interactionGeneration,
                duration: longPressDuration,
                onTap: onPressed,
                onStopImmediately: controller.stopSynchronously,
                onLongPress: onLongPress,
                child: SizedBox(
                  width: 44,
                  height: 44,
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
      },
    );
  }
}

class _ReaderDeliberateHoldGesture extends StatefulWidget {
  const _ReaderDeliberateHoldGesture({
    required this.enabled,
    required this.active,
    required this.interactionGeneration,
    required this.duration,
    required this.onTap,
    required this.onStopImmediately,
    required this.onLongPress,
    required this.child,
  });

  final bool enabled;
  final bool active;
  final int interactionGeneration;
  final Duration duration;
  final VoidCallback onTap;
  final VoidCallback onStopImmediately;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  State<_ReaderDeliberateHoldGesture> createState() =>
      _ReaderDeliberateHoldGestureState();
}

class _ReaderDeliberateHoldGestureState
    extends State<_ReaderDeliberateHoldGesture> {
  Timer? _timer;
  int? _pointer;
  Offset? _origin;
  bool _cancelled = false;
  bool _longPressFired = false;
  bool _stoppedOnDown = false;

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    _origin = event.position;
    _cancelled = false;
    _longPressFired = false;
    _stoppedOnDown = false;
    if (widget.active) {
      _stoppedOnDown = true;
      widget.onStopImmediately();
      return;
    }
    _timer = Timer(widget.duration, () {
      if (!mounted || _cancelled || _pointer == null) return;
      _longPressFired = true;
      widget.onLongPress?.call();
    });
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer || _origin == null) return;
    if ((event.position - _origin!).distance > kTouchSlop) {
      _cancelled = true;
      _timer?.cancel();
    }
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _timer?.cancel();
    if (!_cancelled && !_longPressFired && !_stoppedOnDown) widget.onTap();
    _reset();
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _timer?.cancel();
    _reset();
  }

  void _reset() {
    _pointer = null;
    _origin = null;
    _cancelled = false;
    _longPressFired = false;
    _stoppedOnDown = false;
  }

  @override
  void didUpdateWidget(_ReaderDeliberateHoldGesture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interactionGeneration != widget.interactionGeneration ||
        oldWidget.enabled != widget.enabled) {
      _timer?.cancel();
      _reset();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _cancel,
    child: widget.child,
  );
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
                  const Divider(height: 32),
                  Text(
                    'Status Banner',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  RadioGroup<ReaderTiltStatusBannerMode>(
                    groupValue: current.statusBannerMode,
                    onChanged: (value) {
                      if (value != null) {
                        update(current.copyWith(statusBannerMode: value));
                      }
                    },
                    child: const Column(
                      children: [
                        RadioListTile<ReaderTiltStatusBannerMode>(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Always Visible'),
                          value: ReaderTiltStatusBannerMode.alwaysVisible,
                        ),
                        RadioListTile<ReaderTiltStatusBannerMode>(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Auto-hide after 7 seconds'),
                          value: ReaderTiltStatusBannerMode.autoHide,
                        ),
                        RadioListTile<ReaderTiltStatusBannerMode>(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Always Hidden'),
                          value: ReaderTiltStatusBannerMode.alwaysHidden,
                        ),
                      ],
                    ),
                  ),
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
                              statusBannerMode:
                                  ReaderTiltStatusBannerMode.autoHide,
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

class ReaderTiltAutoScrollActiveIndicator extends StatefulWidget {
  const ReaderTiltAutoScrollActiveIndicator({
    super.key,
    required this.controller,
  });

  final ReaderTiltAutoScrollController controller;

  static const autoHideDuration = Duration(seconds: 7);

  @override
  State<ReaderTiltAutoScrollActiveIndicator> createState() =>
      _ReaderTiltAutoScrollActiveIndicatorState();
}

class _ReaderTiltAutoScrollActiveIndicatorState
    extends State<ReaderTiltAutoScrollActiveIndicator> {
  Timer? _hideTimer;
  bool _autoHideVisible = false;
  late int _seenRevision;

  ReaderTiltAutoScrollController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _seenRevision = controller.statusBannerRevision;
    controller.addListener(_handleControllerChange);
    if (controller.isActive) _showForCurrentMode();
  }

  @override
  void didUpdateWidget(ReaderTiltAutoScrollActiveIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == controller) return;
    oldWidget.controller.removeListener(_handleControllerChange);
    _hideTimer?.cancel();
    _seenRevision = controller.statusBannerRevision;
    controller.addListener(_handleControllerChange);
    _showForCurrentMode();
  }

  void _handleControllerChange() {
    if (_seenRevision == controller.statusBannerRevision) {
      if (mounted) setState(() {});
      return;
    }
    _seenRevision = controller.statusBannerRevision;
    _showForCurrentMode();
  }

  void _showForCurrentMode() {
    _hideTimer?.cancel();
    final mode = controller.preferences.statusBannerMode;
    if (mode != ReaderTiltStatusBannerMode.autoHide) {
      if (mounted) setState(() => _autoHideVisible = false);
      return;
    }
    if (mounted) setState(() => _autoHideVisible = true);
    _hideTimer = Timer(
      ReaderTiltAutoScrollActiveIndicator.autoHideDuration,
      () {
        if (mounted) setState(() => _autoHideVisible = false);
      },
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    controller.removeListener(_handleControllerChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = controller.preferences.statusBannerMode;
    final visible = switch (mode) {
      ReaderTiltStatusBannerMode.alwaysVisible => controller.isActive,
      ReaderTiltStatusBannerMode.autoHide => _autoHideVisible,
      ReaderTiltStatusBannerMode.alwaysHidden => false,
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1,
          child: child,
        ),
      ),
      child: visible
          ? _ReaderTiltStatusBannerContent(
              key: const ValueKey('tilt-status-visible'),
              controller: controller,
            )
          : const SizedBox.shrink(key: ValueKey('tilt-status-hidden')),
    );
  }
}

class _ReaderTiltStatusBannerContent extends StatelessWidget {
  const _ReaderTiltStatusBannerContent({super.key, required this.controller});

  final ReaderTiltAutoScrollController controller;

  @override
  Widget build(BuildContext context) {
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
                !controller.isActive
                    ? 'Tilt Auto-scroll • Off'
                    : calibrating
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
