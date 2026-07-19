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
