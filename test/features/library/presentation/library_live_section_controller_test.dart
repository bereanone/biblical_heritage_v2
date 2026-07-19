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
