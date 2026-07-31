import '../../../core/database/study_bible_database.dart';
import 'viewer_passage_models.dart';
import 'viewer_render_models.dart';

List<ViewerRenderItem> resolveViewerRenderItems(
  PassageData passage, {
  required Map<int, List<String>> headingsByBlockId,
  required Map<int, AcrosticRecord> acrosticsByBlockId,
}) {
  final items = <ViewerRenderItem>[];

  for (final line in passage.lines) {
    final blockId = line.blockId ?? 0;
    final acrostic = acrosticsByBlockId[blockId];
    if (acrostic != null) {
      items.add(
        ViewerAcrosticItem(
          blockId: blockId,
          hebrew: acrostic.hebrew,
          transliteration: acrostic.transliteration,
        ),
      );
    }
    final headings = headingsByBlockId[blockId] ?? const <String>[];
    for (final heading in headings) {
      if (heading.trim().isEmpty) continue;
      items.add(ViewerHeadingItem(blockId: blockId, text: heading));
    }
    items.add(ViewerVerseItem(line: line));
  }

  return items;
}
