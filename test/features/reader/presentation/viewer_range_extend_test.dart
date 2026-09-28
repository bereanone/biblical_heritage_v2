import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_range_selection.dart';

void main() {
  test(
    'extend preserves old range and every intermediate verse in both directions',
    () {
      const initial = ViewerRangeSelection(
        startBlockId: 20,
        endBlockId: 10,
        startTokenIndex: 5,
        endTokenIndex: 2,
      );
      final down = initial.extendVerseRange(250);
      for (var id = 10; id <= 250; id++) {
        expect(down.containsBlock(id), isTrue);
      }
      final up = down.extendVerseRange(2);
      expect(up.lowerBlockId, 2);
      expect(up.upperBlockId, 250);
      expect(up.extendVerseRange(50).upperBlockId, 250);
      expect(up.hasTokenSelection, isFalse);
      expect(up.clear().hasSelection, isFalse);
    },
  );
}
