import 'package:flutter/material.dart';

/// Shared help for books opened from the library, Commentary, or Research.
class LibraryReaderHelpButton extends StatelessWidget {
  const LibraryReaderHelpButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Reader Help',
    icon: const Icon(Icons.help_outline),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('eLibrary Reader Help'),
        content: const SingleChildScrollView(
          child: Text(
            'Autoscroll and voice\n\n'
            'Long press the Autoscroll button to open its settings. '
            'On Mac, turn Audio off and select Save to scroll silently. '
            'The up and down controls then adjust scrolling speed.\n\n'
            'With Audio on, narration sets the reading pace, and the up and '
            'down controls adjust voice speed. The Voice button starts or '
            'pauses narration. Choosing Read aloud turns Audio on again.\n\n'
            'On iPhone, iPad, and Android, full books play saved recordings '
            'only; they do not generate book narration on the device. '
            'If no recording is available, download one to listen.\n\n'
            'Use Contents to jump to a heading and Day or Night to change '
            'the reading appearance.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}
