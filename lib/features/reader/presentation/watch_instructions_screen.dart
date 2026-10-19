import 'package:flutter/material.dart';

class WatchInstructionsScreen extends StatelessWidget {
  const WatchInstructionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const sections = <(String, String)>[
      (
        'Open Bible Remote',
        'Install the Watch companion through the iPhone Watch app. Add Bible Remote to a supported watch-face complication. Tap it to open the remote. Playback controls are inside the remote; the face launcher does not start playback.',
      ),
      (
        'Start, stop, and pause',
        'Start begins playback on the connected iPhone. Stop stops it, and Pause pauses it. The Watch controls the phone; it does not store or play the narration itself. Connect your headset to the iPhone to listen there.',
      ),
      (
        'Choose a passage',
        'Choose Book, Chapter, or Verse. Tap Choose book, Choose chapter, or Choose verse below the loop controls. Turn the Crown in the picker, then tap Go to. Chapters belong to the current book, and verses belong to the current chapter. A passage jump leaves playback paused; tap Start when ready.',
      ),
      (
        'Previous and Next',
        'These buttons follow the selected unit: book, chapter, or verse. Selecting a unit does not by itself engage a loop.',
      ),
      (
        'Repeat a passage',
        'Select Book, Chapter, or Verse, then tap Engage to repeat the current target. The selected unit has a checkmark and a Selected label. Check the loop status at the top to confirm the active loop. Tap Off to turn looping off.',
      ),
      (
        'If the iPhone is unavailable',
        'Keep the devices connected and open StudyBible on the iPhone, then retry. A connected status confirms communication, not that a newer Watch update is installed. If new controls are missing, check installation progress in the iPhone Watch app.',
      ),
      (
        'Memory reminders — planned',
        'Memory reminders are not available yet. The planned Watch reminder will offer Listen and Dismiss. Passage selection, schedules, and all practice drills will stay on the phone.',
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Bible Remote Instructions')),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: 24),
        itemBuilder: (context, index) {
          final section = sections[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.$1,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(section.$2),
            ],
          );
        },
      ),
    );
  }
}
