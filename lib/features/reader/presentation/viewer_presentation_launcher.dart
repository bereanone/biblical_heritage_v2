import 'package:flutter/material.dart';

import '../../../core/theme/app_settings_service.dart';
import '../data/presentation/presentation_grouping_adapter.dart';
import '../data/presentation/presentation_models.dart';
import 'tag_quick_apply_helper.dart';
import 'viewer_presentation_screen.dart';

Future<void> showPresentationLaunchOptions(
  BuildContext context, {
  required List<HashTagEntry> entries,
  required int initialIndex,
  required String tag,
  required String tagFamily,
}) async {
  final slides = await const PresentationGroupingAdapter().adaptEntries(
    entries,
  );
  if (slides.isEmpty) return;
  final initialSlideIndex = _initialSlideIndexForEntry(
    slides: slides,
    entries: entries,
    initialIndex: initialIndex,
  );
  if (!context.mounted) return;
  await showViewerPresentationScreen(
    context,
    slides: slides,
    initialIndex: initialSlideIndex,
  );
}

Future<void> showViewerPresentationScreen(
  BuildContext context, {
  required List<PresentationSlide> slides,
  required int initialIndex,
}) async {
  if (slides.isEmpty) return;
  final preset = await AppSettingsService.instance
      .loadPresentationAspectRatioPreset();
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ViewerPresentationScreen(
        slides: slides,
        initialIndex: initialIndex,
        aspectRatioPreset: preset,
      ),
    ),
  );
}

int _initialSlideIndexForEntry({
  required List<PresentationSlide> slides,
  required List<HashTagEntry> entries,
  required int initialIndex,
}) {
  if (slides.isEmpty) return 0;
  if (entries.isEmpty) return initialIndex.clamp(0, slides.length - 1);

  final entry = entries[initialIndex.clamp(0, entries.length - 1)];
  final entryId = entry.id.toString();
  final slideIndex = slides.indexWhere(
    (slide) => slide.items.any((item) => item.legacyItemId == entryId),
  );
  if (slideIndex >= 0) return slideIndex;
  return initialIndex.clamp(0, slides.length - 1);
}
