import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/cross_reference_panel.dart';
import 'package:studybible2/features/reader/presentation/viewer_passage_models.dart';
import 'package:studybible2/features/reader/presentation/viewer_verse_line.dart';

void main() {
  test('active autoscroll consumes the first cross-reference tap', () {
    expect(
      crossReferenceTapStopsAutoscroll(
        tiltAutoscrollActive: true,
        steadyAutoscrollActive: false,
      ),
      isTrue,
    );
    expect(
      crossReferenceTapStopsAutoscroll(
        tiltAutoscrollActive: false,
        steadyAutoscrollActive: true,
      ),
      isTrue,
    );
    expect(
      crossReferenceTapStopsAutoscroll(
        tiltAutoscrollActive: false,
        steadyAutoscrollActive: false,
      ),
      isFalse,
    );
  });

  testWidgets(
    'verse-number tap is isolated from verse-text tap and long press',
    (tester) async {
      var numberTaps = 0;
      var textTaps = 0;
      var gutterLongPresses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ViewerVerseLine(
              line: const VerseLine(
                blockId: 26137,
                bookNumber: 43,
                chapter: 3,
                verse: 16,
                html: 'For God so loved the world',
                text: 'For God so loved the world',
              ),
              style: const TextStyle(fontSize: 18),
              isSelected: false,
              onTap: () => textTaps++,
              onVerseNumberTap: () => numberTaps++,
              onVerseNumberLongPress: () => gutterLongPresses++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('16'));
      expect(numberTaps, 1);
      expect(textTaps, 0);

      final verseText = find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('For God so loved the world'),
      );
      await tester.tap(verseText);
      expect(numberTaps, 1);
      expect(textTaps, 1);

      await tester.longPress(find.text('16'));
      expect(gutterLongPresses, 1);
      expect(numberTaps, 1);
      expect(textTaps, 1);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('16')),
      );
      await gesture.moveBy(const Offset(0, 40));
      await gesture.up();
      expect(numberTaps, 1, reason: 'a drag must cancel the margin tap');
    },
  );

  testWidgets('panel queries source ID and lazily displays canonical KJV rows', (
    tester,
  ) async {
    int? queriedId;
    int? selectedId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CrossReferencePanel(
            sourceVerseId: 26137,
            sourceReference: 'John 3:16',
            loadItems: (sourceVerseId) async {
              queriedId = sourceVerseId;
              return const [
                CrossReferenceListItem(
                  targetVerseId: 28072,
                  reference: 'Romans 5:8',
                  text:
                      'But God commendeth his love toward us, in that, while we were yet sinners, Christ died for us.',
                ),
                CrossReferenceListItem(
                  targetVerseId: 30589,
                  reference: '1 John 4:9',
                  text: 'In this was manifested the love of God toward us.',
                ),
              ];
            },
            onSelect: (value) => selectedId = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(queriedId, 26137);
    expect(find.text('John 3:16'), findsOneWidget);
    expect(find.text('Cross References'), findsOneWidget);
    expect(find.text('Romans 5:8'), findsOneWidget);
    expect(
      find.text(
        'But God commendeth his love toward us, in that, while we were yet sinners, Christ died for us.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('cross-reference-list')), findsOneWidget);

    await tester.tap(find.text('Romans 5:8'));
    expect(selectedId, 28072);
  });

  testWidgets('panel shows the Revelation empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CrossReferencePanel(
            sourceVerseId: 30939,
            sourceReference: 'Revelation 14:12',
            loadItems: (_) async => const [],
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No cross references available for this verse.'),
      findsOneWidget,
    );
  });

  testWidgets('panel query error is recoverable', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CrossReferencePanel(
            sourceVerseId: 26137,
            sourceReference: 'John 3:16',
            loadItems: (_) async {
              attempts++;
              if (attempts == 1) throw StateError('database unavailable');
              return const [];
            },
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cross references could not be loaded.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(
      find.text('No cross references available for this verse.'),
      findsOneWidget,
    );
  });

  testWidgets('many cross references remain scrollable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CrossReferencePanel(
            sourceVerseId: 1,
            sourceReference: 'Genesis 1:1',
            loadItems: (_) async => List.generate(
              150,
              (index) => CrossReferenceListItem(
                targetVerseId: index + 2,
                reference: 'Reference ${index + 1}',
                text: 'Excerpt ${index + 1}',
              ),
            ),
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reference 1'), findsOneWidget);
    expect(find.text('Reference 150'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Reference 150'),
      1000,
      scrollable: find.descendant(
        of: find.byKey(const Key('cross-reference-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Reference 150'), findsOneWidget);
  });
}
