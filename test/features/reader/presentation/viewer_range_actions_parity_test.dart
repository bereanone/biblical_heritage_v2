import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_range_actions_sheet.dart';

void main() {
  testWidgets(
    'Bible retains range tools including Extend Range from the reference menu',
    (tester) async {
      ViewerRangeAction? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await showViewerRangeActionsSheet(
                    context,
                    payload: const ViewerRangeActionsPayload(
                      label: '2 Corinthians 4:10',
                      previewText: 'of the Lord',
                      startLabel: '2 Corinthians 4:10',
                      endLabel: '2 Corinthians 4:10',
                    ),
                    fontScale: 1,
                    enableStrongs: true,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      final actions = {
        'Copy No Citation': ViewerRangeAction.copyNoCitation,
        'Copy With Citation': ViewerRangeAction.copyWithCitation,
        'Highlight': ViewerRangeAction.highlight,
        'Clear Markup': ViewerRangeAction.clearMarkup,
        'Add # Tag': ViewerRangeAction.addHashTag,
        'Choose # Tag': ViewerRangeAction.addDollarTag,
        'Add to Memory': ViewerRangeAction.addToMemory,
        "Strong's": ViewerRangeAction.strongs,
        'Extend Range': ViewerRangeAction.extendRange,
        'Reset Range': ViewerRangeAction.resetRange,
      };
      for (final action in actions.entries) {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(action.key),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text(action.key));
        await tester.pumpAndSettle();
        expect(chosen, action.value);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
