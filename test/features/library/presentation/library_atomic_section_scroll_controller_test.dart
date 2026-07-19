import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:studybible2/features/library/presentation/library_atomic_section_scroll_controller.dart';

void main() {
  test('one section transition receives exactly one initial offset', () {
    final controller = LibraryAtomicSectionScrollController();
    addTearDown(controller.dispose);
    controller.requestInitialEdge(
      generation: 4,
      edge: LibrarySectionInitialEdge.top,
    );

    expect(
      controller.takePendingOffset(minScrollExtent: 0, maxScrollExtent: 900),
      0,
    );
    expect(
      controller.takePendingOffset(minScrollExtent: 0, maxScrollExtent: 900),
      isNull,
    );
    expect(controller.initialOffsetRequests, 1);
    expect(controller.initialOffsetsApplied, 1);
    expect(controller.lastAppliedGeneration, 4);
  });

  test('reverse transition applies the new section bottom once', () {
    final controller = LibraryAtomicSectionScrollController();
    addTearDown(controller.dispose);
    controller.requestInitialEdge(
      generation: 5,
      edge: LibrarySectionInitialEdge.bottom,
    );

    expect(
      controller.takePendingOffset(minScrollExtent: 0, maxScrollExtent: 1250),
      1250,
    );
    expect(controller.initialOffsetsApplied, 1);
  });

  test('invalid layout cannot consume the pending section offset', () {
    final controller = LibraryAtomicSectionScrollController();
    addTearDown(controller.dispose);
    controller.requestInitialEdge(
      generation: 6,
      edge: LibrarySectionInitialEdge.top,
    );

    expect(
      controller.takePendingOffset(
        minScrollExtent: double.nan,
        maxScrollExtent: double.infinity,
      ),
      isNull,
    );
    expect(controller.initialOffsetsApplied, 0);
    expect(
      controller.takePendingOffset(minScrollExtent: 0, maxScrollExtent: 700),
      0,
    );
  });

  test('old generation cannot schedule a second offset', () {
    final controller = LibraryAtomicSectionScrollController();
    addTearDown(controller.dispose);
    controller.requestInitialEdge(
      generation: 8,
      edge: LibrarySectionInitialEdge.top,
    );
    controller.takePendingOffset(minScrollExtent: 0, maxScrollExtent: 500);

    controller.requestInitialEdge(
      generation: 7,
      edge: LibrarySectionInitialEdge.bottom,
    );
    expect(
      controller.takePendingOffset(minScrollExtent: 0, maxScrollExtent: 500),
      isNull,
    );
    expect(controller.staleOffsetRequestsRejected, 1);
    expect(controller.initialOffsetsApplied, 1);
  });

  test('heading and page publication wait for the settled generation', () {
    expect(
      librarySectionTransitionCanPublish(
        currentGeneration: 3,
        callbackGeneration: 2,
        attachedPositionCount: 1,
        hasValidContentDimensions: true,
        appliedOffsetGeneration: 2,
      ),
      isFalse,
    );
    expect(
      librarySectionTransitionCanPublish(
        currentGeneration: 3,
        callbackGeneration: 3,
        attachedPositionCount: 1,
        hasValidContentDimensions: false,
        appliedOffsetGeneration: null,
      ),
      isFalse,
    );
    expect(
      librarySectionTransitionCanPublish(
        currentGeneration: 3,
        callbackGeneration: 3,
        attachedPositionCount: 1,
        hasValidContentDimensions: true,
        appliedOffsetGeneration: 3,
      ),
      isTrue,
    );
  });

  testWidgets('new section paints at its one requested initial edge', (
    tester,
  ) async {
    final controller = LibraryAtomicSectionScrollController();
    addTearDown(controller.dispose);
    var itemCount = 40;
    late StateSetter setBodyState;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 300,
          child: StatefulBuilder(
            builder: (context, setState) {
              setBodyState = setState;
              return ListView.builder(
                controller: controller,
                itemExtent: 50,
                itemCount: itemCount,
                itemBuilder: (context, index) => Text('row $index'),
              );
            },
          ),
        ),
      ),
    );
    controller.jumpTo(600);
    controller.requestInitialEdge(
      generation: 9,
      edge: LibrarySectionInitialEdge.top,
    );
    setBodyState(() => itemCount = 20);
    await tester.pump();

    expect(controller.offset, controller.position.minScrollExtent);
    expect(controller.initialOffsetRequests, 1);
    expect(controller.initialOffsetsApplied, 1);
    expect(controller.positions, hasLength(1));
  });
}
