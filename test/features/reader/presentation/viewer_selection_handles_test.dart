import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/text_range_geometry.dart';
import 'package:studybible2/features/reader/presentation/viewer_range_selection.dart';
import 'package:studybible2/features/reader/presentation/viewer_selection_handles.dart';

void main() {
  test(
    'either endpoint expands or shrinks across verses without swapping handles',
    () {
      const selection = ViewerRangeSelection(
        startBlockId: 10,
        startTokenIndex: 3,
        endBlockId: 11,
        endTokenIndex: 6,
      );
      final expanded = selection.moveEndpoint(
        start: true,
        blockId: 9,
        tokenIndex: 2,
      );
      expect(expanded.lowerBlockId, 9);
      expect(expanded.upperBlockId, 11);
      final shrunk = expanded.moveEndpoint(
        start: false,
        blockId: 10,
        tokenIndex: 4,
      );
      expect(shrunk.upperBlockId, 10);
      expect(shrunk.upperTokenIndex, 4);
      final clamped = selection.moveEndpoint(
        start: true,
        blockId: 12,
        tokenIndex: 1,
      );
      expect(clamped.isSingleToken, isTrue);
      expect(clamped.startBlockId, 11);
      expect(clamped.startTokenIndex, 6);
    },
  );
  testWidgets(
    'handles appear after selection, drag independently and disappear when cleared',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 500);
      addTearDown(tester.view.reset);
      final registry = TextRangeGeometryRegistry();
      addTearDown(registry.dispose);
      for (var token = 1; token <= 4; token++) {
        final rect = Rect.fromLTWH(80.0 + token * 60, 180, 50, 24);
        registry.register(
          TextRangeGeometry(
            anchor: TextRangeAnchor.bible(
              scopeId: 'test',
              verseBlockId: 10,
              tokenIndex: token,
            ),
            localRect: rect,
            globalRect: rect,
            textDirection: TextDirection.ltr,
          ),
        );
      }
      var selection = const ViewerRangeSelection(
        startBlockId: 10,
        startTokenIndex: 2,
        endBlockId: 10,
        endTokenIndex: 3,
      );
      var moves = 0;
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                change = setState;
                return ViewerSelectionHandles(
                  registry: registry,
                  selection: selection,
                  onDismiss: () => setState(() => selection = selection.clear()),
                  onMove: (start, block, token) {
                    moves++;
                    setState(
                      () => selection = selection.moveEndpoint(
                        start: start,
                        blockId: block,
                        tokenIndex: token,
                      ),
                    );
                  },
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final start = find.byKey(const ValueKey('viewer-selection-start-handle'));
      final end = find.byKey(const ValueKey('viewer-selection-end-handle'));
      expect(start, findsOneWidget);
      expect(end, findsOneWidget);
      await tester.drag(end, const Offset(75, 0));
      await tester.pump();
      expect(moves, greaterThan(0));
      expect(selection.lowerTokenIndex, 2);
      expect(selection.upperTokenIndex, 4);
      await tester.drag(start, const Offset(-75, 0));
      await tester.pump();
      expect(selection.lowerTokenIndex, 1);
      await tester.tapAt(const Offset(195, 190));
      await tester.pump();
      expect(selection.hasCompletedRange, isTrue);
      await tester.tapAt(const Offset(560, 330));
      await tester.pump();
      expect(selection.hasSelection, isFalse);
      change(() => selection = const ViewerRangeSelection());
      await tester.pump();
      expect(start, findsNothing);
      expect(end, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
