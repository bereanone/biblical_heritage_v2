import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../library/presentation/mac_reader_autoscroll_controller.dart';
import 'bible_loop_announcement_settings.dart';

/// Bible setup uses the existing preference stores; opening it changes nothing.
class BibleAudioSettings extends StatefulWidget {
  const BibleAudioSettings({
    super.key,
    required this.controller,
    required this.onPreferencesChanged,
    required this.onPronunciations,
    required this.onAnnouncementChanged,
    this.announcements,
    this.onDiagnosticReport,
  });

  final Future<String> Function()? onDiagnosticReport;
  final MacReaderAutoScrollController controller;
  final ValueChanged<MacAutoscrollPreferences> onPreferencesChanged;
  final VoidCallback onPronunciations;
  final void Function(BibleLoopUnit, bool) onAnnouncementChanged;
  // Recorded narration has independently saved book, chapter and verse cues.
  // Generated speech retains its existing combined book/chapter preference.
  final BibleLoopAnnouncementSettings? announcements;

  @override
  State<BibleAudioSettings> createState() => _BibleAudioSettingsState();
}

class _BibleAudioSettingsState extends State<BibleAudioSettings> {
  late BibleLoopAnnouncementSettings? _announcements = widget.announcements;

  bool _openingReport = false;

  Future<void> _openReport() async {
    if (_openingReport) return;
    setState(() => _openingReport = true);
    String report;
    try {
      report = await widget.onDiagnosticReport!();
    } catch (_) {
      report = 'The audio report could not be read. Please try again.';
    }
    if (!mounted) return;
    setState(() => _openingReport = false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Audio report'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This report shows playback status and recent audio events. It stays on your device unless you share it.',
                ),
                const SizedBox(height: 12),
                SelectableText(report),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Audio report copied.')),
                  );
                }
              }
            },
            child: const Text('Copy report'),
          ),
        ],
      ),
    );
  }

  void _update({bool? audio, double? rate, bool? chapter, bool? verses}) {
    final c = widget.controller;
    final next = MacAutoscrollPreferences(
      baseSpeed: c.baseSpeed,
      lastNonzeroStep: c.lastNonzeroStep,
      maximumStep: c.maximumStep,
      statusBannerMode: c.statusBannerMode,
      audioEnabled: audio ?? c.audioEnabled,
      speechRate: rate ?? c.speechRate,
      announceChapter: chapter ?? c.announceChapter,
      announceVerseNumbers: verses ?? c.announceVerseNumbers,
    );
    // Turning audio off must pause playback, never start silent scrolling.
    if (audio == false) c.stopForManualInteraction();
    c.updatePreferences(next);
    widget.onPreferencesChanged(next);
  }

  Widget _announcement(BibleLoopUnit unit, String title) =>
      SwitchListTile.adaptive(
        key: ValueKey('bible-audio-announce-${unit.name}'),
        title: Text(title),
        value: _announcements!.enabledFor(unit),
        onChanged: (enabled) {
          setState(() {
            _announcements = _announcements!.withValue(unit, enabled);
          });
          widget.onAnnouncementChanged(unit, enabled);
        },
      );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Bible Audio Settings',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                trailing: IconButton(
                  tooltip: 'Close audio settings',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              SwitchListTile.adaptive(
                key: const ValueKey('bible-audio-enabled'),
                title: const Text('Read aloud'),
                subtitle: const Text(
                  'Enable Bible audio. Use Play Bible to start.',
                ),
                value: controller.audioEnabled,
                onChanged: (value) => _update(audio: value),
              ),
              ListTile(
                title: const Text('Voice speed'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${controller.speechRate.toStringAsFixed(2)}×'),
                    if (Theme.of(context).platform ==
                        TargetPlatform.android) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        key: const ValueKey('android-bible-audio-normal-speed'),
                        onPressed: controller.speechRate == 1.0
                            ? null
                            : () => _update(rate: 1.0),
                        child: const Text('Use 1.00×'),
                      ),
                    ],
                  ],
                ),
              ),
              if (Theme.of(context).platform == TargetPlatform.android)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Android compatibility: starts at 1.05× each app launch '
                    'to prevent silent Bible audio on some phones. You can '
                    'lower it for this session; restarting restores 1.05×.',
                    key: const ValueKey('android-bible-audio-compatibility'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Slider(
                key: const ValueKey('bible-audio-speed'),
                value: controller.speechRate,
                min: 0.75,
                max: 1.5,
                divisions: 15,
                label: '${controller.speechRate.toStringAsFixed(2)}×',
                onChanged: (value) => _update(rate: value),
              ),
              const Divider(),
              const ListTile(title: Text('Announcements')),
              if (_announcements != null) ...[
                _announcement(BibleLoopUnit.book, 'Book name'),
                _announcement(BibleLoopUnit.chapter, 'Chapter number'),
                _announcement(BibleLoopUnit.verse, 'Verse number'),
              ] else ...[
                SwitchListTile.adaptive(
                  title: const Text('Book and chapter'),
                  value: controller.announceChapter,
                  onChanged: (value) => _update(chapter: value),
                ),
                SwitchListTile.adaptive(
                  title: const Text('Verse number'),
                  value: controller.announceVerseNumbers,
                  onChanged: (value) => _update(verses: value),
                ),
              ],
              if (widget.onDiagnosticReport != null) ...[
                const Divider(),
                ListTile(
                  key: const ValueKey('bible-audio-report'),
                  title: const Text('Audio report'),
                  subtitle: const Text(
                    'Help troubleshoot playback. Nothing is sent automatically.',
                  ),
                  trailing: const Icon(Icons.info_outline),
                  enabled: !_openingReport,
                  onTap: _openReport,
                ),
              ],
              const Divider(),
              ListTile(
                key: const ValueKey('bible-audio-pronunciations'),
                title: const Text('Pronunciations'),
                subtitle: Text(
                  _announcements != null
                      ? 'For generated speech only. These edits do not change the recorded Bible voice.'
                      : 'Edit pronunciation for generated speech.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onPronunciations();
                },
              ),
            ],
          );
        },
      ),
    ),
  );
}
