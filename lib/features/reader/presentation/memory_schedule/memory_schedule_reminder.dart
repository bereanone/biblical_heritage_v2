import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/bible_memory_repository.dart';
import '../bible_memory_audio.dart';
import '../tag_playback/tag_playback_popup.dart';
import 'memory_schedule.dart';

Future<void> showMemoryAudioReminder(
  BuildContext context,
  MemoryAudioTarget target,
) async {
  final listen = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Time to listen'),
      content: Text(target.label),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Dismiss'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.headphones_rounded),
          label: const Text('Listen'),
        ),
      ],
    ),
  );
  if (listen != true || !context.mounted) return;
  if (target.memoryId != null) {
    final items = await BibleMemoryRepository().loadAll();
    final passage = items.where((p) => p.id == target.memoryId).firstOrNull;
    if (!context.mounted) return;
    if (passage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This memory passage is no longer in the list.'),
        ),
      );
      return;
    }
    await showMemoryAudioPopup(context, passage, autoStart: true);
  } else {
    await showTagPlaybackPopup(
      context,
      tag: target.tag!,
      category: target.category,
      isDollar: target.isDollar,
      autoStart: true,
    );
  }
}

/// Foreground Mac prototype; this is not an OS alarm or a background notifier.
class MacMemoryReminderService {
  MacMemoryReminderService(this.navigator);
  final GlobalKey<NavigatorState> navigator;
  Timer? _timer;
  bool _checking = false, _disposed = false;
  void start() {
    if (!Platform.isMacOS) return;
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_check()),
    );
  }

  Future<void> _check() async {
    if (_checking || _disposed) return;
    final context = navigator.currentState?.overlay?.context;
    if (context == null || !context.mounted) return;
    _checking = true;
    try {
      final now = DateTime.now();
      final all = await MemoryAudioScheduleStore.instance.load();
      for (final schedule in all) {
        final stamp = schedule.occurrence(now);
        if (stamp == null || _disposed || !context.mounted) continue;
        // Mark before presenting: dismissal and restarts cannot retrigger this minute.
        final due = await MemoryAudioScheduleStore.instance.claimDue(
          schedule.target.key,
          DateTime.now(),
        );
        if (due != null && !_disposed && context.mounted) {
          await showMemoryAudioReminder(context, due.target);
          break;
        }
      }
    } catch (error) {
      // Keep existing data intact. A storage failure is retried on a later tick.
      debugPrint('Memory reminder check failed: $error');
    } finally {
      _checking = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
