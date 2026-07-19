import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_body.dart';

void main() {
  test('stale old-range visible callbacks are rejected', () {
    expect(
      viewerVisibleLocationCallbackIsCurrent(
        scheduledGeneration: 4,
        currentGeneration: 5,
      ),
      isFalse,
    );
    expect(
      viewerVisibleLocationCallbackIsCurrent(
        scheduledGeneration: 5,
        currentGeneration: 5,
      ),
      isTrue,
    );
  });

  test('Bible extends its loaded window before autoscroll reaches blanks', () {
    expect(
      viewerAutoScrollWindowAction(
        delta: 5,
        firstVisibleBlockId: 140,
        lastVisibleBlockId: 148,
        firstLoadedBlockId: 100,
        lastLoadedBlockId: 150,
        maxBlockId: 1000,
      ),
      ViewerAutoScrollWindowAction.extendForward,
    );
  });

  test('Bible keeps scrolling inside loaded content', () {
    expect(
      viewerAutoScrollWindowAction(
        delta: 5,
        firstVisibleBlockId: 120,
        lastVisibleBlockId: 128,
        firstLoadedBlockId: 100,
        lastLoadedBlockId: 150,
        maxBlockId: 1000,
      ),
      ViewerAutoScrollWindowAction.scroll,
    );
  });

  test('Bible stops safely at its actual final boundary', () {
    expect(
      viewerAutoScrollWindowAction(
        delta: 5,
        firstVisibleBlockId: 992,
        lastVisibleBlockId: 1000,
        firstLoadedBlockId: 950,
        lastLoadedBlockId: 1000,
        maxBlockId: 1000,
      ),
      ViewerAutoScrollWindowAction.stopAtEnd,
    );
  });

  test('Bible loads backward without crossing its loaded start', () {
    expect(
      viewerAutoScrollWindowAction(
        delta: -5,
        firstVisibleBlockId: 101,
        lastVisibleBlockId: 108,
        firstLoadedBlockId: 100,
        lastLoadedBlockId: 150,
        maxBlockId: 1000,
      ),
      ViewerAutoScrollWindowAction.extendBackward,
    );
  });

  test('Bible body never exposes unloaded forward rows as empty content', () {
    var lastLoaded = 100;
    for (var range = 0; range < 5; range++) {
      final itemCount = viewerBodyItemCountForLoadedWindow(lastLoaded);
      expect(itemCount, lastLoaded);
      expect(itemCount + 1, greaterThan(itemCount));
      lastLoaded += 15;
    }
    expect(viewerBodyItemCountForLoadedWindow(null), 0);
  });
}
