import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_continuous_section_window.dart';

void main() {
  LibraryContinuousSectionUnit<String> unit(int index) =>
      LibraryContinuousSectionUnit<String>(
        identity: 'chapter-$index.xhtml',
        headingPath: <String>['Part A', 'Chapter $index'],
        bodyBlocks: <String>['ending/opening text $index'],
        sourcePageMarkers: <int, String>{0: 'page-${index * 10}'},
      );

  test(
    'previous ending, current heading, and next body share one document',
    () {
      const window = LibraryContinuousSectionWindow(
        readableIndices: <int>[1, 2, 3, 4],
        centerIndex: 2,
      );
      final mounted = libraryContinuousMountedUnits(
        window: window,
        unitsByIndex: <int, LibraryContinuousSectionUnit<String>>{
          for (var index = 1; index <= 4; index++) index: unit(index),
        },
      );

      expect(mounted.map((value) => value.identity), <String>[
        'chapter-1.xhtml',
        'chapter-2.xhtml',
        'chapter-3.xhtml',
      ]);
      expect(mounted.first.bodyBlocks.last, contains('text 1'));
      expect(mounted[1].headingPath.last, 'Chapter 2');
      expect(mounted[1].bodyBlocks.first, contains('text 2'));
      expect(mounted.last.headingPath.last, 'Chapter 3');
      expect(mounted.last.bodyBlocks.first, contains('text 3'));
    },
  );

  test('heading identity remains stable when live center advances', () {
    const before = LibraryContinuousSectionWindow(
      readableIndices: <int>[1, 2, 3, 4],
      centerIndex: 2,
    );
    final after = before.moveTo(3)!;
    final units = <int, LibraryContinuousSectionUnit<String>>{
      for (var index = 1; index <= 4; index++) index: unit(index),
    };

    final beforeChapter3 = libraryContinuousMountedUnits(
      window: before,
      unitsByIndex: units,
    ).singleWhere((value) => value.identity == 'chapter-3.xhtml');
    final afterChapter3 = libraryContinuousMountedUnits(
      window: after,
      unitsByIndex: units,
    ).singleWhere((value) => value.identity == 'chapter-3.xhtml');

    expect(identical(beforeChapter3, afterChapter3), isTrue);
    expect(afterChapter3.headingPath, <String>['Part A', 'Chapter 3']);
  });

  test('window remains bounded through hundreds of boundaries', () {
    final indices = List<int>.generate(500, (index) => index);
    var window = LibraryContinuousSectionWindow(
      readableIndices: indices,
      centerIndex: 0,
    );
    for (var index = 1; index < indices.length; index++) {
      window = window.moveTo(index)!;
      expect(window.isBounded, isTrue);
      expect(window.mountedIndices.length, lessThanOrEqualTo(3));
    }
  });

  test('non-adjacent movement is rejected and cannot skip sections', () {
    const window = LibraryContinuousSectionWindow(
      readableIndices: <int>[2, 3, 9],
      centerIndex: 2,
    );
    expect(window.moveTo(9), isNull);
    expect(window.moveTo(3)?.centerIndex, 3);
  });

  test('prepending and removing above preserve the visual anchor', () {
    expect(
      libraryContinuousWindowCompensatedOffset(
        oldOffset: 900,
        removedAboveHeight: 300,
      ),
      600,
    );
    expect(
      libraryContinuousWindowCompensatedOffset(
        oldOffset: 600,
        prependedAboveHeight: 300,
      ),
      900,
    );
  });

  test('source page markers stay owned by stable source blocks', () {
    final chapter = unit(4);
    const before = LibraryContinuousSectionWindow(
      readableIndices: <int>[3, 4, 5, 6],
      centerIndex: 3,
    );
    final after = before.moveTo(4)!;
    final units = <int, LibraryContinuousSectionUnit<String>>{
      3: unit(3),
      4: chapter,
      5: unit(5),
      6: unit(6),
    };
    expect(
      libraryContinuousMountedUnits(
        window: before,
        unitsByIndex: units,
      )[1].sourcePageMarkers,
      <int, String>{0: 'page-40'},
    );
    expect(
      libraryContinuousMountedUnits(
        window: after,
        unitsByIndex: units,
      )[1].sourcePageMarkers,
      <int, String>{0: 'page-40'},
    );
  });

  test('live section is derived from the first meaningful visible unit', () {
    final visible = libraryFirstMeaningfulVisibleSection(
      mountedIndices: const <int>[4, 5, 6],
      sectionTopOffsets: const <int, double>{4: 0, 5: 700, 6: 1400},
      viewportOffset: 710,
    );
    expect(visible, 5);
  });

  test('fresh Chapter 1 window can exclude front matter above', () {
    const window = LibraryContinuousSectionWindow(
      readableIndices: <int>[0, 1, 2, 3],
      centerIndex: 1,
      minimumReadablePosition: 1,
    );
    expect(window.mountedIndices, <int>[1, 2]);
  });

  test('intentional front-matter selection still mounts front matter', () {
    const window = LibraryContinuousSectionWindow(
      readableIndices: <int>[0, 1, 2, 3],
      centerIndex: 0,
    );
    expect(window.mountedIndices, <int>[0, 1]);
  });
}
