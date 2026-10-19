import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_live_section_controller.dart';

void main() {
  LibraryLiveSectionLocation location({
    required String navigationId,
    required String entryName,
    required String label,
    required int generation,
  }) => LibraryLiveSectionLocation(
    navigationId: navigationId,
    sectionEntryName: entryName,
    headingLabels: <String>[label],
    generation: generation,
  );

  const labels = {
    'support': 'Ellen White’s Support',
    'chapter-1': 'Chapter 1 — Living By Faith',
    'chapter-2': 'Chapter 2 — Lessons On Faith',
  };

  test('shared EPUB file does not keep Contents on its first entry', () {
    expect(
      libraryLiveContentsNavigationId(
        location: location(
          navigationId: 'support',
          entryName: 'book.xhtml',
          label: 'Chapter 1 — Living By Faith',
          generation: 1,
        ),
        labelsById: labels,
        fallbackId: 'support',
      ),
      'chapter-1',
    );
  });

  test('Contents advances with live heading despite stale navigation ID', () {
    final controller = LibraryLiveSectionController();
    addTearDown(controller.dispose);
    final selections = <String?>[];
    controller.addListener(
      () => selections.add(
        libraryLiveContentsNavigationId(
          location: controller.value,
          labelsById: labels,
          fallbackId: 'support',
        ),
      ),
    );
    for (var chapter = 1; chapter <= 2; chapter++) {
      controller.update(
        location(
          navigationId: 'support',
          entryName: 'book.xhtml',
          label: labels['chapter-$chapter']!,
          generation: chapter,
        ),
      );
    }
    expect(selections, ['chapter-1', 'chapter-2']);
  });

  test('Contents tolerates heading punctuation and preserves fallback', () {
    expect(
      libraryLiveContentsNavigationId(
        location: location(
          navigationId: 'support',
          entryName: 'book.xhtml',
          label: 'CHAPTER 1 - Living By Faith',
          generation: 1,
        ),
        labelsById: labels,
      ),
      'chapter-1',
    );
    expect(
      libraryLiveContentsNavigationId(
        location: null,
        labelsById: labels,
        fallbackId: 'chapter-2',
      ),
      'chapter-2',
    );
  });

  test('duplicate headings do not select an unrelated chapter', () {
    expect(
      libraryLiveContentsNavigationId(
        location: location(
          navigationId: 'second',
          entryName: 'two.xhtml',
          label: 'Introduction',
          generation: 1,
        ),
        labelsById: {'first': 'Introduction', 'second': 'Introduction'},
      ),
      'second',
    );
  });

  test('initial and subsequent readable sections remain current', () {
    final controller = LibraryLiveSectionController();
    addTearDown(controller.dispose);

    expect(
      controller.update(
        location(
          navigationId: 'chapter-1',
          entryName: 'chapter-1.xhtml',
          label: 'Chapter 1',
          generation: 1,
        ),
      ),
      isTrue,
    );
    expect(controller.value?.displayLabel, 'Chapter 1');

    expect(
      controller.update(
        location(
          navigationId: 'chapter-2',
          entryName: 'chapter-2.xhtml',
          label: 'Chapter 2',
          generation: 2,
        ),
      ),
      isTrue,
    );
    expect(controller.value?.displayLabel, 'Chapter 2');
  });

  test('manual and tilt publication of the same identity do not duplicate', () {
    final controller = LibraryLiveSectionController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    final next = location(
      navigationId: 'chapter-2',
      entryName: 'chapter-2.xhtml',
      label: 'Chapter 2',
      generation: 2,
    );
    expect(controller.update(next), isTrue);
    expect(
      controller.update(
        location(
          navigationId: 'chapter-2',
          entryName: 'chapter-2.xhtml',
          label: 'Chapter 2',
          generation: 3,
        ),
      ),
      isFalse,
    );
    expect(notifications, 1);
    expect(controller.value, same(next));
  });

  test('stale completion cannot replace the visible chapter', () {
    final controller = LibraryLiveSectionController();
    addTearDown(controller.dispose);

    controller.update(
      location(
        navigationId: 'chapter-2',
        entryName: 'chapter-2.xhtml',
        label: 'Chapter 2',
        generation: 8,
      ),
    );
    expect(
      controller.update(
        location(
          navigationId: 'chapter-1',
          entryName: 'chapter-1.xhtml',
          label: 'Chapter 1',
          generation: 7,
        ),
      ),
      isFalse,
    );
    expect(controller.value?.displayLabel, 'Chapter 2');
    expect(controller.rejectedStaleUpdates, 1);
  });
}
