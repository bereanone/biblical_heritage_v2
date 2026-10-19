import 'dart:async';

import '../memory_schedule/memory_schedule.dart';
import '../memory_schedule/memory_schedule_editor.dart';
import '../memory_schedule/memory_schedule_reminder.dart';

import 'package:flutter/material.dart';

import '../../../../core/audio/narration_media_session.dart';
import '../tag_dialog_styles.dart';
import 'tag_playback_panel.dart';
import 'tag_playback_session.dart';

/// Opens the "listen to this tag" popup. Dismissing it (tap outside, back,
/// close button) stops playback and cancels any pending synthesis.
Future<void> showTagPlaybackPopup(
  BuildContext context, {
  required String tag,
  String? category,
  bool isDollar = false,
  double fontScale = 1,
  bool autoStart = false,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return showDialog<void>(
    context: navigator.context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final size = TagDialogStyles.detailModalSize(
        MediaQuery.of(dialogContext).size,
      );
      return Dialog(
        insetPadding: TagDialogStyles.outerInset,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TagDialogStyles.borderRadius),
        ),
        clipBehavior: Clip.antiAlias,
        backgroundColor: TagDialogStyles.surface(theme),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: TagPlaybackDialog(
            tag: tag,
            fontScale: fontScale,
            autoStart: autoStart,
            onSchedule: () {
              final target = MemoryAudioTarget(
                label: tag,
                tag: tag,
                category: category,
                isDollar: isDollar,
              );
              return showMemoryScheduleEditor(
                dialogContext,
                target,
                preview: () => showMemoryAudioReminder(dialogContext, target),
              );
            },
            open: () => TagPlaybackSession.open(
              tag: tag,
              category: category,
              isDollar: isDollar,
            ),
          ),
        ),
      );
    },
  );
}

/// Owns the playback session for exactly as long as the popup is on screen.
class TagPlaybackDialog extends StatefulWidget {
  const TagPlaybackDialog({
    super.key,
    required this.tag,
    required this.open,
    this.fontScale = 1,
    this.autoStart = false,
    this.onSchedule,
  });

  final String tag;
  final Future<TagPlaybackSession> Function() open;
  final double fontScale;
  final bool autoStart;
  final Future<void> Function()? onSchedule;

  @override
  State<TagPlaybackDialog> createState() => _TagPlaybackDialogState();
}

class _TagPlaybackDialogState extends State<TagPlaybackDialog>
    with WidgetsBindingObserver {
  TagPlaybackSession? _session;
  Object? _error;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.open().then(
      (session) {
        // Dismissed while the tag and engine were still loading.
        if (_closed) {
          session.dispose();
          return;
        }
        setState(() => _session = session);
        if (widget.autoStart) {
          session.pauseOtherSessions();
          session.controller.play();
        }
      },
      onError: (Object error) {
        if (!_closed && mounted) setState(() => _error = error);
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Where the OS allows it (iOS audio background mode) speech keeps going
    // behind a locked screen and TagPlaybackMediaBinding buffers deeper.
    // Elsewhere nothing keeps speaking in the background. macOS window focus
    // loss ("inactive") deliberately keeps playing; only real backgrounding
    // pauses.
    if (NarrationMediaSession.instance.supported) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _session?.controller.pauseForBackground();
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _session?.dispose();
    _session = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Listen · ${widget.tag}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TagDialogStyles.titleTextStyle(
                    theme,
                    widget.fontScale,
                    color: TagDialogStyles.title(theme),
                  ),
                ),
              ),
              if (widget.onSchedule != null)
                IconButton(
                  tooltip: 'Listening schedule',
                  icon: const Icon(Icons.schedule),
                  onPressed: widget.onSchedule,
                ),
              IconButton(
                key: const Key('tag_playback_close'),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: session != null
              ? TagPlaybackPanel(
                  controller: session.controller,
                  fontScale: widget.fontScale,
                )
              : Center(
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Could not load this tag for playback.\n$_error',
                            textAlign: TextAlign.center,
                            style: TagDialogStyles.bodyTextStyle(
                              theme,
                              widget.fontScale,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        )
                      : const CircularProgressIndicator(),
                ),
        ),
      ],
    );
  }
}
