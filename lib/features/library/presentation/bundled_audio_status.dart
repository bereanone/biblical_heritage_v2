import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../data/bundled_audio_setup.dart';
import '../../../core/bootstrap/bundled_content_platform.dart';

class BundledAudioStatus extends StatefulWidget {
  const BundledAudioStatus({super.key, this.sourceHashes = const {}});
  final Set<String> sourceHashes;
  @override
  State<BundledAudioStatus> createState() => _BundledAudioStatusState();
}

class _BundledAudioStatusState extends State<BundledAudioStatus> {
  static const _readyDuration = Duration(seconds: 4);
  Timer? _completionTimer;

  void _scheduleCompletionHide() {
    _completionTimer?.cancel();
    final completedAt = BundledAudioSetup.instance.completedAt;
    if (completedAt == null) return;
    final remaining = _readyDuration - DateTime.now().difference(completedAt);
    if (remaining > Duration.zero) {
      _completionTimer = Timer(remaining, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    BundledAudioSetup.instance.removeListener(_scheduleCompletionHide);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    BundledAudioSetup.instance.addListener(_scheduleCompletionHide);
    _scheduleCompletionHide();
    if (bundledContentEnabled) {
      BundledAudioSetup.instance.ensure(sourceHashes: widget.sourceHashes);
    }
  }

  @override
  void didUpdateWidget(covariant BundledAudioStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (bundledContentEnabled &&
        !setEquals(oldWidget.sourceHashes, widget.sourceHashes)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          BundledAudioSetup.instance.ensure(sourceHashes: widget.sourceHashes);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!bundledContentEnabled) return const SizedBox.shrink();
    final setup = BundledAudioSetup.instance;
    return ListenableBuilder(
      listenable: setup,
      builder: (context, _) {
        if (setup.complete) {
          final completedAt = setup.completedAt;
          if (completedAt == null ||
              DateTime.now().difference(completedAt) >= _readyDuration) {
            return const SizedBox.shrink();
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Included recordings are ready.'),
          );
        }
        if (!setup.showProgress && setup.error == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(setup.message),
              if (setup.running) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: setup.progress),
                const Text(
                  'Keep the app open while recordings download. You can continue reading.',
                ),
              ],
              if (setup.error != null) ...[
                Text(
                  setup.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton.icon(
                  onPressed: () =>
                      setup.ensure(sourceHashes: widget.sourceHashes),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry recordings'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
