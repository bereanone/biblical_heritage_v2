import 'package:flutter/material.dart';

import '../tag_dialog_styles.dart';
import 'tag_playback_controller.dart';

/// The playback settings that decide what is spoken, grouped by what they
/// govern: what introduces every entry, and the notes attached to them. Loop
/// is not here: it lives in the transport row where it is used mid-playback.
class TagPlaybackSettingsPanel extends StatelessWidget {
  const TagPlaybackSettingsPanel({
    super.key,
    required this.controller,
    this.fontScale = 1,
  });

  final TagPlaybackController controller;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = TagDialogStyles.bodyTextStyle(theme, fontScale);
    final small = style.copyWith(fontSize: (style.fontSize ?? 15) - 2);
    final heading = style.copyWith(
      fontWeight: FontWeight.w800,
      color: TagDialogStyles.accent(theme),
    );
    return Card(
      key: const Key('tag_playback_settings_panel'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      elevation: 0,
      color: TagDialogStyles.accent(theme).withValues(alpha: 0.08),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Entry introductions', style: heading),
          ),
          SwitchListTile(
            key: const Key('tag_playback_setting_reference'),
            dense: true,
            title: Text('Speak reference', style: style),
            subtitle: Text(
              'Say each entry’s reference or title before it: the verse, the '
              'book and location, or the note’s title',
              style: small,
            ),
            value: controller.speakReference,
            onChanged: controller.setSpeakReference,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Notes', style: heading),
          ),
          SwitchListTile(
            key: const Key('tag_playback_setting_notes'),
            dense: true,
            title: Text('Speak notes', style: style),
            subtitle: Text(
              'Read each entry’s note after its content',
              style: small,
            ),
            value: controller.includeNotes,
            onChanged: controller.setIncludeNotes,
          ),
        ],
      ),
    );
  }
}
