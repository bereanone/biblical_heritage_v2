import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/bible_visible_location_controller.dart';

BibleVisibleLocation location(
  int blockId, {
  int book = 1,
  int chapter = 1,
  int? verse,
}) => BibleVisibleLocation(
  blockId: blockId,
  bookNumber: book,
  chapter: chapter,
  verse: verse ?? blockId,
);

void main() {
  const canonicalBookNames = <String>[
    'Genesis',
    'Exodus',
    'Leviticus',
    'Numbers',
    'Deuteronomy',
    'Joshua',
    'Judges',
    'Ruth',
    '1 Samuel',
    '2 Samuel',
    '1 Kings',
    '2 Kings',
    '1 Chronicles',
    '2 Chronicles',
    'Ezra',
    'Nehemiah',
    'Esther',
    'Job',
    'Psalms',
    'Proverbs',
    'Ecclesiastes',
    'Song of Solomon',
    'Isaiah',
    'Jeremiah',
    'Lamentations',
    'Ezekiel',
    'Daniel',
    'Hosea',
    'Joel',
    'Amos',
    'Obadiah',
    'Jonah',
    'Micah',
    'Nahum',
    'Habakkuk',
    'Zephaniah',
    'Haggai',
    'Zechariah',
    'Malachi',
    'Matthew',
    'Mark',
    'Luke',
    'John',
    'Acts',
    'Romans',
    '1 Corinthians',
    '2 Corinthians',
    'Galatians',
    'Ephesians',
    'Philippians',
    'Colossians',
    '1 Thessalonians',
    '2 Thessalonians',
    '1 Timothy',
    '2 Timothy',
    'Titus',
    'Philemon',
    'Hebrews',
    'James',
    '1 Peter',
    '2 Peter',
    '1 John',
    '2 John',
    '3 John',
    'Jude',
    'Revelation',
  ];
  final canonicalNamesByNumber = <int, String>{
    for (var index = 0; index < canonicalBookNames.length; index++)
      index + 1: canonicalBookNames[index],
  };

  test('all 66 canonical identifiers resolve without an off-by-one shift', () {
    expect(canonicalBookNames, hasLength(66));
    for (var bookNumber = 1; bookNumber <= 66; bookNumber++) {
      final visible = location(
        bookNumber * 1000,
        book: bookNumber,
        chapter: 1,
        verse: 1,
      );
      final resolved = resolveBibleReaderLocation(
        visibleLocation: visible,
        fallbackLocation: location(
          999,
          book: bookNumber == 1 ? 2 : bookNumber - 1,
        ),
        bookNamesByNumber: canonicalNamesByNumber,
      );
      expect(resolved.bookNumber, bookNumber);
      expect(resolved.bookName, canonicalBookNames[bookNumber - 1]);
      expect(resolved.label, '${canonicalBookNames[bookNumber - 1]} 1:1');
    }
  });

  test('boundary transitions replace stale fallback header locations', () {
    final cases =
        <({BibleVisibleLocation from, BibleVisibleLocation to, String label})>[
          (
            from: location(211212, book: 21, chapter: 12, verse: 12),
            to: location(220101, book: 22, chapter: 1, verse: 1),
            label: 'Song of Solomon 1:1',
          ),
          (
            from: location(390406, book: 39, chapter: 4, verse: 6),
            to: location(400101, book: 40, chapter: 1, verse: 1),
            label: 'Matthew 1:1',
          ),
          (
            from: location(442831, book: 44, chapter: 28, verse: 31),
            to: location(450101, book: 45, chapter: 1, verse: 1),
            label: 'Romans 1:1',
          ),
          (
            from: location(90101, book: 9, chapter: 1, verse: 1),
            to: location(100101, book: 10, chapter: 1, verse: 1),
            label: '2 Samuel 1:1',
          ),
        ];

    for (final testCase in cases) {
      final resolved = resolveBibleReaderLocation(
        visibleLocation: testCase.to,
        fallbackLocation: testCase.from,
        bookNamesByNumber: canonicalNamesByNumber,
      );
      expect(resolved.label, testCase.label);
    }
  });

  test('direct jump and restored endpoints become the authoritative label', () {
    final live = BibleLiveReferenceController();
    addTearDown(live.dispose);

    live.update(location(1, book: 1, chapter: 1, verse: 1));
    expect(
      resolveBibleReaderLocation(
        visibleLocation: live.value,
        fallbackLocation: location(777, book: 21, chapter: 12, verse: 12),
        bookNamesByNumber: canonicalNamesByNumber,
      ).label,
      'Genesis 1:1',
    );

    live.update(location(662221, book: 66, chapter: 22, verse: 21));
    expect(
      resolveBibleReaderLocation(
        visibleLocation: live.value,
        fallbackLocation: location(1),
        bookNamesByNumber: canonicalNamesByNumber,
      ).label,
      'Revelation 22:21',
    );
  });

  test('selected verse overrides centered and first-available verses', () {
    final live = BibleLiveReferenceController();
    addTearDown(live.dispose);
    live.updateFirstAvailable(location(1, book: 1, chapter: 1, verse: 1));
    live.updateCentered(location(211209, book: 21, chapter: 12, verse: 9));
    live.updateSelected(location(211212, book: 21, chapter: 12, verse: 12));

    expect(live.value!.verse, 12);
    live.updateCentered(location(220104, book: 22, chapter: 1, verse: 4));
    expect(live.value!.bookNumber, 21);
    expect(live.value!.verse, 12);
  });

  test('manual selection release promotes the centered verse', () {
    final live = BibleLiveReferenceController();
    addTearDown(live.dispose);
    live.updateSelected(location(220101, book: 22, chapter: 1, verse: 1));
    live.updateCentered(location(220104, book: 22, chapter: 1, verse: 4));
    expect(live.value!.verse, 1);

    live.clearSelected();
    expect(live.value!.verse, 4);
  });

  test('direct navigation target survives premature visibility callbacks', () {
    final live = BibleLiveReferenceController();
    addTearDown(live.dispose);
    live.updateSelected(location(220101, book: 22, chapter: 1, verse: 1));
    live.updateCentered(location(211212, book: 21, chapter: 12, verse: 12));
    live.updateCentered(location(220104, book: 22, chapter: 1, verse: 4));

    expect(live.value!.bookNumber, 22);
    expect(live.value!.chapter, 1);
    expect(live.value!.verse, 1);
  });

  test('selected override releases once live centering settles on that verse, '
      'so scrolling away keeps updating the label instead of freezing', () {
    final live = BibleLiveReferenceController();
    addTearDown(live.dispose);

    // Reader opens at Genesis 1:23 (an explicit selection/navigation).
    final opened = location(1023, book: 1, chapter: 1, verse: 23);
    live.updateSelected(opened);
    expect(live.value, opened);

    // The scroll list settles on the exact opened verse (recenter completes).
    live.updateCentered(opened);
    expect(live.value, opened);

    // No drag-based "manual scroll" signal ever fires (e.g. macOS
    // autoscroll or a mouse-wheel/trackpad scroll instead of a drag), but
    // live centering keeps reporting new verses as the reader scrolls.
    final genesis416 = location(1120, book: 1, chapter: 4, verse: 16);
    live.updateCentered(genesis416);

    expect(live.value, isNot(opened));
    expect(live.value!.bookNumber, 1);
    expect(live.value!.chapter, 4);
    expect(live.value!.verse, 16);
  });

  test(
    'settled selection continues to track further live centering updates',
    () {
      final live = BibleLiveReferenceController();
      addTearDown(live.dispose);
      final selected = location(220101, book: 22, chapter: 1, verse: 1);
      live.updateSelected(selected);
      live.updateCentered(selected);

      live.updateCentered(location(220102, book: 22, chapter: 1, verse: 2));
      expect(live.value!.verse, 2);
      live.updateCentered(location(220103, book: 22, chapter: 1, verse: 3));
      expect(live.value!.verse, 3);
    },
  );

  test('center resolver ignores headings and partially visible top verses', () {
    final centered = centeredBibleVerseBlockId(const [
      BibleViewportCandidate(
        blockId: 9,
        leadingEdge: -0.25,
        trailingEdge: 0.08,
        isVerse: true,
      ),
      BibleViewportCandidate(
        blockId: 10,
        leadingEdge: 0.30,
        trailingEdge: 0.47,
        isVerse: false,
      ),
      BibleViewportCandidate(
        blockId: 12,
        leadingEdge: 0.44,
        trailingEdge: 0.69,
        isVerse: true,
      ),
      BibleViewportCandidate(
        blockId: 13,
        leadingEdge: 0.69,
        trailingEdge: 0.92,
        isVerse: true,
      ),
    ]);

    expect(centered, 12);
  });

  test('center resolver chooses nearest verse when center is on a heading', () {
    final centered = centeredBibleVerseBlockId(const [
      BibleViewportCandidate(
        blockId: 20,
        leadingEdge: 0.31,
        trailingEdge: 0.43,
        isVerse: true,
      ),
      BibleViewportCandidate(
        blockId: 21,
        leadingEdge: 0.43,
        trailingEdge: 0.57,
        isVerse: false,
      ),
      BibleViewportCandidate(
        blockId: 22,
        leadingEdge: 0.57,
        trailingEdge: 0.72,
        isVerse: true,
      ),
    ]);

    expect(centered, 20);
  });

  test('live reference updates across chapter and book boundaries', () {
    final live = BibleLiveReferenceController();
    addTearDown(live.dispose);

    live.update(location(1, chapter: 1));
    live.update(location(31, chapter: 2, verse: 1));
    expect(live.value!.chapter, 2);
    live.update(location(1001, book: 2, chapter: 1, verse: 1));
    expect(live.value!.bookNumber, 2);
    expect(live.updateCount, 3);
  });

  test('hundreds of autoscroll changes create no writes until Stop and then '
      'save the latest location once', () async {
    final live = BibleLiveReferenceController();
    addTearDown(live.dispose);
    final writes = <BibleVisibleLocation>[];
    final coordinator = BibleLocationPersistenceCoordinator(
      writer: (value) async => writes.add(value),
      throttle: const Duration(milliseconds: 1),
    );
    addTearDown(coordinator.dispose);

    for (var index = 1; index <= 300; index++) {
      live.update(location(index, chapter: 1 + index ~/ 30));
      coordinator.update(
        location(index, chapter: 1 + index ~/ 30),
        persistenceSuspended: true,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(writes, isEmpty);
    expect(live.updateCount, 300);
    expect(coordinator.pendingLocationCount, 1);

    await coordinator.resumeAndFlush();
    expect(writes, hasLength(1));
    expect(writes.single.blockId, 300);
    expect(coordinator.writesCompleted, 1);
  });

  test(
    'multiple requested positions replace pending data with latest',
    () async {
      final writes = <BibleVisibleLocation>[];
      final coordinator = BibleLocationPersistenceCoordinator(
        writer: (value) async => writes.add(value),
      );
      addTearDown(coordinator.dispose);

      coordinator.update(location(10), persistenceSuspended: true);
      coordinator.update(location(20), persistenceSuspended: true);
      coordinator.update(location(30), persistenceSuspended: true);
      expect(coordinator.pendingLocationCount, 1);
      expect(coordinator.latest!.blockId, 30);
      await coordinator.resumeAndFlush();
      expect(writes.map((value) => value.blockId), [30]);
    },
  );

  test('one active write is permitted and an in-flight replacement stays '
      'bounded', () async {
    final firstWrite = Completer<void>();
    final writes = <BibleVisibleLocation>[];
    final coordinator = BibleLocationPersistenceCoordinator(
      writer: (value) async {
        writes.add(value);
        if (writes.length == 1) await firstWrite.future;
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.update(location(1), persistenceSuspended: false);
    final flush = coordinator.flush();
    await Future<void>.delayed(Duration.zero);
    coordinator.update(location(2), persistenceSuspended: false);
    coordinator.update(location(3), persistenceSuspended: false);
    firstWrite.complete();
    await flush;

    expect(writes.map((value) => value.blockId), [1, 3]);
    expect(coordinator.maximumOverlappingWrites, 1);
    expect(coordinator.pendingLocationCount, 0);
  });

  test(
    'navigation persistence represents one bounded Recent location',
    () async {
      final simulatedNavigationRow = <int, BibleVisibleLocation>{};
      final coordinator = BibleLocationPersistenceCoordinator(
        writer: (value) async => simulatedNavigationRow[1] = value,
        throttle: const Duration(milliseconds: 1),
      );
      addTearDown(coordinator.dispose);

      for (var index = 1; index <= 100; index++) {
        coordinator.update(location(index), persistenceSuspended: true);
      }
      await coordinator.resumeAndFlush();
      expect(simulatedNavigationRow, hasLength(1));
      expect(simulatedNavigationRow[1]!.blockId, 100);
    },
  );

  test('same location does not rebuild the live reference indicator', () {
    final live = BibleLiveReferenceController();
    addTearDown(live.dispose);
    var indicatorBuildSignals = 0;
    live.addListener(() => indicatorBuildSignals += 1);
    final visible = location(7);

    live.update(visible);
    live.update(visible);
    live.update(visible);
    expect(indicatorBuildSignals, 1);
  });
}
