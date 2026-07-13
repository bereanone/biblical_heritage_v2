import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';

void main() {
  final threshold = 15 * math.pi / 180;
  final start = DateTime.utc(2026, 1, 1);

  ReaderChapterTiltDirection? update(
    ReaderHorizontalChapterGesture gesture,
    double degrees,
    int milliseconds, {
    bool reverse = false,
    bool boundary = true,
    bool movingQuickly = false,
  }) => gesture.update(
    relativeHorizontalRadians: degrees * math.pi / 180,
    thresholdRadians: threshold,
    reverseDirection: reverse,
    boundaryApproved: boundary,
    verticalMovingQuickly: movingQuickly,
    now: start.add(Duration(milliseconds: milliseconds)),
  );

  test('brief or below-threshold tilt does not trigger', () {
    final gesture = ReaderHorizontalChapterGesture();
    expect(update(gesture, 10, 0), isNull);
    expect(update(gesture, 17, 0), isNull);
    expect(update(gesture, 17, 300), isNull);
  });

  test('sustained right and left tilts select next and previous', () {
    final right = ReaderHorizontalChapterGesture();
    update(right, 17, 0);
    expect(update(right, 17, 600), ReaderChapterTiltDirection.next);

    final left = ReaderHorizontalChapterGesture();
    update(left, -17, 0);
    expect(update(left, -17, 600), ReaderChapterTiltDirection.previous);
  });

  test('reversed direction swaps next and previous', () {
    final gesture = ReaderHorizontalChapterGesture();
    update(gesture, 17, 0, reverse: true);
    expect(
      update(gesture, 17, 600, reverse: true),
      ReaderChapterTiltDirection.previous,
    );
  });

  test('gesture fires once, requires neutral, and observes cooldown', () {
    final gesture = ReaderHorizontalChapterGesture();
    update(gesture, 17, 0);
    expect(update(gesture, 17, 600), ReaderChapterTiltDirection.next);
    expect(update(gesture, 17, 800), isNull);
    update(gesture, 0, 900);
    update(gesture, 17, 1000);
    expect(update(gesture, 17, 1700), isNull);
    update(gesture, 0, 1800);
    update(gesture, 17, 1900);
    expect(update(gesture, 17, 2500), ReaderChapterTiltDirection.next);
  });

  test('boundary rejection and fast vertical movement prevent trigger', () {
    final gesture = ReaderHorizontalChapterGesture();
    update(gesture, 17, 0, boundary: false);
    expect(update(gesture, 17, 600, boundary: false), isNull);
    update(gesture, 17, 700, movingQuickly: true);
    expect(update(gesture, 17, 1400, movingQuickly: true), isNull);
  });

  test('reset cancels a pending gesture', () {
    final gesture = ReaderHorizontalChapterGesture();
    update(gesture, 17, 0);
    gesture.reset();
    expect(update(gesture, 17, 600), isNull);
  });

  group('section boundary tolerance', () {
    test('bottom approves next but not previous', () {
      final boundary = readerSectionBoundaryState(
        pixels: 960,
        minScrollExtent: 0,
        maxScrollExtent: 1000,
      );
      expect(boundary.atBottom, isTrue);
      expect(boundary.atTop, isFalse);
    });

    test('top approves previous but not next', () {
      final boundary = readerSectionBoundaryState(
        pixels: 40,
        minScrollExtent: 0,
        maxScrollExtent: 1000,
      );
      expect(boundary.atTop, isTrue);
      expect(boundary.atBottom, isFalse);
    });

    test('middle approves neither direction', () {
      final boundary = readerSectionBoundaryState(
        pixels: 500,
        minScrollExtent: 0,
        maxScrollExtent: 1000,
      );
      expect(boundary.atTop, isFalse);
      expect(boundary.atBottom, isFalse);
    });

    test('short section approves both directions', () {
      final boundary = readerSectionBoundaryState(
        pixels: 0,
        minScrollExtent: 0,
        maxScrollExtent: 0,
      );
      expect(boundary.atTop, isTrue);
      expect(boundary.atBottom, isTrue);
    });

    test('tolerance is inclusive and configurable', () {
      expect(
        readerSectionBoundaryState(
          pixels: 952,
          minScrollExtent: 0,
          maxScrollExtent: 1000,
        ).atBottom,
        isTrue,
      );
      expect(
        readerSectionBoundaryState(
          pixels: 951,
          minScrollExtent: 0,
          maxScrollExtent: 1000,
        ).atBottom,
        isFalse,
      );
    });
  });
}
