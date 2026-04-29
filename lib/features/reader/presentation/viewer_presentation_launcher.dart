import 'package:flutter/material.dart';

import '../../../core/theme/app_settings_service.dart';
import 'tag_quick_apply_helper.dart';
import 'viewer_presentation_screen.dart';

Future<void> showViewerPresentationScreen(
  BuildContext context, {
  required List<HashTagEntry> entries,
  required int initialIndex,
}) async {
  if (entries.isEmpty) return;
  final preset = await AppSettingsService.instance
      .loadPresentationAspectRatioPreset();
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ViewerPresentationScreen(
        entries: entries,
        initialIndex: initialIndex,
        aspectRatioPreset: preset,
      ),
    ),
  );
}
