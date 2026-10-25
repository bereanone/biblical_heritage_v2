import 'package:flutter/material.dart';

import 'mac_reader_autoscroll_controller.dart';

/// Audio transport cannot change the saved Audio On/Off preference.
/// Silent autoscroll is movement, not narration playback.
class ReaderNarrationButton extends StatelessWidget {
  const ReaderNarrationButton({
    super.key,
    required this.controller,
    this.playLabel = 'Read aloud',
    this.pauseLabel = 'Pause',
    this.busy = false,
    this.onPause,
    this.onChanged,
    this.onLongPress,
    this.audioOffHint =
        'Audio is off. Enable Audio in autoscroll settings to listen.',
  });

  final MacReaderAutoScrollController controller;
  final String playLabel;
  final String pauseLabel;
  final bool busy;
  final VoidCallback? onPause;
  final VoidCallback? onChanged;
  final VoidCallback? onLongPress;
  final String audioOffHint;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final audioEnabled = controller.audioEnabled;
      final playing = audioEnabled && controller.isScrolling;
      return Tooltip(
        message: audioEnabled
            ? (playing ? pauseLabel : playLabel)
            : audioOffHint,
        child: TextButton.icon(
          icon: Icon(
            !audioEnabled
                ? Icons.volume_off_outlined
                : (playing ? Icons.pause : Icons.play_arrow),
          ),
          label: Text(
            !audioEnabled ? 'Audio off' : (playing ? pauseLabel : playLabel),
          ),
          onPressed: !audioEnabled || busy
              ? null
              : () {
                  // Recheck after rebuilding: a settings change must not be undone
                  // by a stale transport callback.
                  if (!controller.audioEnabled) return;
                  if (controller.isScrolling) {
                    if (onPause != null) {
                      onPause!();
                    } else {
                      controller.setSignedStep(0);
                    }
                  } else {
                    controller.setSignedStep(1);
                  }
                  onChanged?.call();
                },
          onLongPress: audioEnabled && !busy ? onLongPress : null,
        ),
      );
    },
  );
}
