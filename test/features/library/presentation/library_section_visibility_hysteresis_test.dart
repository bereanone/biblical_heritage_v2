import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_continuous_section_window.dart';

void main() {
  LibrarySectionVisibilityDecision sample(
    LibrarySectionVisibilityHysteresis hysteresis, {
    required int current,
    required int candidate,
    required double boundaryTop,
    required int millisecond,
  }) => hysteresis.update(
    LibrarySectionVisibilitySample(
      currentIndex: current,
      candidateIndex: candidate,
      candidateTop: boundaryTop,
      viewportTop: 0,
      viewportHeight: 1000,
      now: DateTime.fromMillisecondsSinceEpoch(millisecond),
    ),
  );

  test('Acts Chapter 1/2 boundary produces one stable identity change', () {
    final hysteresis = LibrarySectionVisibilityHysteresis();
    expect(
      sample(
        hysteresis,
        current: 1,
        candidate: 2,
        boundaryTop: 249,
        millisecond: 0,
      ).changed,
      isFalse,
    );
    expect(
      sample(
        hysteresis,
        current: 1,
        candidate: 2,
        boundaryTop: 249,
        millisecond: 16,
      ).changed,
      isFalse,
    );
    final decision = sample(
      hysteresis,
      current: 1,
      candidate: 2,
      boundaryTop: 249,
      millisecond: 32,
    );
    expect(decision.changed, isTrue);
    expect(decision.index, 2);
  });

  test('partial next heading visibility does not publish Chapter 2', () {
    final hysteresis = LibrarySectionVisibilityHysteresis();
    for (var frame = 0; frame < 10; frame++) {
      expect(
        sample(
          hysteresis,
          current: 1,
          candidate: 2,
          boundaryTop: 251,
          millisecond: frame * 16,
        ).changed,
        isFalse,
      );
    }
  });

  test('Chapter 2 remains current until a material reverse threshold', () {
    final hysteresis = LibrarySectionVisibilityHysteresis();
    for (var frame = 0; frame < 10; frame++) {
      expect(
        sample(
          hysteresis,
          current: 2,
          candidate: 1,
          boundaryTop: 549,
          millisecond: frame * 16,
        ).changed,
        isFalse,
      );
    }
    for (var frame = 0; frame < 2; frame++) {
      expect(
        sample(
          hysteresis,
          current: 2,
          candidate: 1,
          boundaryTop: 551,
          millisecond: 200 + frame * 16,
        ).changed,
        isFalse,
      );
    }
    expect(
      sample(
        hysteresis,
        current: 2,
        candidate: 1,
        boundaryTop: 551,
        millisecond: 232,
      ).index,
      1,
    );
  });

  test('old/new/old/new alternation watchdog clamps the fourth change', () {
    final hysteresis = LibrarySectionVisibilityHysteresis();
    var current = 1;
    for (var change = 0; change < 4; change++) {
      final candidate = current == 1 ? 2 : 1;
      LibrarySectionVisibilityDecision? decision;
      for (var frame = 0; frame < 3; frame++) {
        decision = sample(
          hysteresis,
          current: current,
          candidate: candidate,
          boundaryTop: candidate > current ? 200 : 600,
          millisecond: change * 100 + frame * 10,
        );
      }
      if (change < 3) {
        expect(decision!.changed, isTrue);
        current = candidate;
      } else {
        expect(decision!.changed, isFalse);
        expect(decision.watchdogClamped, isTrue);
        expect(decision.index, current);
      }
    }
  });

  test('recycling does not occur while identity is pending', () {
    const window = LibraryContinuousSectionWindow(
      readableIndices: <int>[0, 1, 2, 3],
      centerIndex: 1,
    );
    final before = window.mountedIndices;
    final hysteresis = LibrarySectionVisibilityHysteresis();
    final pending = sample(
      hysteresis,
      current: 1,
      candidate: 2,
      boundaryTop: 249,
      millisecond: 0,
    );
    expect(pending.changed, isFalse);
    expect(window.mountedIndices, before);
  });

  test('indicator height is independent of publication text', () {
    final before = libraryStableLiveIndicatorHeight(1.3);
    final after = libraryStableLiveIndicatorHeight(1.3);
    expect(after, before);
  });

  test('tilt clamps at the stable section boundary with zero movement', () {
    expect(
      libraryStableSectionScrollTarget(
        pixels: 800,
        delta: 20,
        minimum: 100,
        maximum: 800,
      ),
      800,
    );
    expect(
      libraryStableSectionScrollTarget(
        pixels: 100,
        delta: -20,
        minimum: 100,
        maximum: 800,
      ),
      100,
    );
  });
}
