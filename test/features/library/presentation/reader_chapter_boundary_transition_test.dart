import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_book_reader_screen.dart';
import 'package:studybible2/features/library/presentation/library_continuous_section_window.dart';

void main() {
  const readable = <int>[0, 3, 5, 8];

  test('manual downward scrolling reveals one adjacent readable section', () {
    const window = LibraryContinuousSectionWindow(
      readableIndices: readable,
      centerIndex: 0,
    );
    expect(window.mountedIndices, <int>[0, 3]);
    expect(window.moveTo(3)?.mountedIndices, <int>[0, 3, 5]);
  });

  test('manual upward scrolling reveals the previous readable section', () {
    const window = LibraryContinuousSectionWindow(
      readableIndices: readable,
      centerIndex: 5,
    );
    expect(window.mountedIndices, <int>[3, 5, 8]);
    expect(window.moveTo(3)?.mountedIndices, <int>[0, 3, 5]);
  });

  test('manual and tilt vertical scrolling use the same document order', () {
    const manualWindow = LibraryContinuousSectionWindow(
      readableIndices: readable,
      centerIndex: 3,
    );
    const tiltWindow = LibraryContinuousSectionWindow(
      readableIndices: readable,
      centerIndex: 3,
    );
    expect(manualWindow.mountedIndices, tiltWindow.mountedIndices);
    expect(manualWindow.moveTo(5)?.centerIndex, 5);
    expect(tiltWindow.moveTo(5)?.centerIndex, 5);
  });

  test('vertical chapter-transition callback policy remains disabled', () {
    expect(elibraryAutomaticTiltChapterTransitionsEnabled, isFalse);
  });

  test('non-adjacent request cannot jump Chapter 2 to Chapter 9', () {
    const window = LibraryContinuousSectionWindow(
      readableIndices: <int>[2, 3, 9],
      centerIndex: 2,
    );
    expect(window.moveTo(9), isNull);
    expect(window.moveTo(3)?.centerIndex, 3);
  });

  test('true book boundaries retain their visible units', () {
    const start = LibraryContinuousSectionWindow(
      readableIndices: readable,
      centerIndex: 0,
    );
    const end = LibraryContinuousSectionWindow(
      readableIndices: readable,
      centerIndex: 8,
    );
    expect(start.moveTo(-1), isNull);
    expect(start.mountedIndices, isNotEmpty);
    expect(end.moveTo(9), isNull);
    expect(end.mountedIndices, isNotEmpty);
  });
}
