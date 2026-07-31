import '../data/highlights_repository.dart';
import 'viewer_passage_models.dart';
import 'viewer_range_selection.dart';

Future<bool> applyDefaultMarkup({
  required int groupId,
  required ViewerRangeSelection rangeSelection,
  required PassageData passage,
  required bool Function(VerseLine) isLineInRange,
  required List<TokenHighlightSelection> Function(List<VerseLine>)
  buildTokenSelections,
}) async {
  if (!rangeSelection.hasCompletedRange) return false;
  final selectedLines = passage.lines.where(isLineInRange).toList();
  if (selectedLines.isEmpty) return false;
  final verseRefs = selectedLines
      .map((l) => '${passage.bookName} ${l.chapter}:${l.verse}')
      .toList(growable: false);
  if (rangeSelection.hasTokenSelection) {
    await HighlightsRepository().applyHighlightToTokenRanges(
      groupId: groupId,
      selections: buildTokenSelections(selectedLines),
    );
  } else {
    await HighlightsRepository().applyHighlightToVerseRefs(
      groupId: groupId,
      verseRefs: verseRefs,
    );
  }
  return true;
}
