import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_book_label.dart';
import 'package:studybible2/features/reader/presentation/viewer_inline_number_grid.dart';

void main() {
  testWidgets('larger book selector keeps its color and a usable tap target', (
    tester,
  ) async {
    var taps = 0;
    final fontSize = ValueNotifier<double>(19);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 150,
              child: ValueListenableBuilder<double>(
                valueListenable: fontSize,
                builder: (context, size, _) => ViewerBookLabel(
                  label: '1 Thessalonians',
                  color: Colors.deepPurple,
                  selected: false,
                  fontSize: size,
                  minimumTapHeight: 48,
                  expandWidth: true,
                  onTap: () => taps++,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(InkWell)).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.getSize(find.byType(InkWell)).width, 150);
    expect(
      tester.widget<Text>(find.text('1 Thessalonians')).style?.fontSize,
      19,
    );
    fontSize.value = 22.5;
    await tester.pump();
    expect(
      tester.widget<Text>(find.text('1 Thessalonians')).style?.fontSize,
      22.5,
    );
    fontSize.value = 30.2;
    await tester.pump();
    expect(
      tester.widget<Text>(find.text('1 Thessalonians')).style?.fontSize,
      30.2,
    );
    expect(tester.widget<Text>(find.text('1 Thessalonians')).maxLines, 4);
    expect(tester.getSize(find.byType(InkWell)).width, 150);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(ViewerBookLabel),
        matching: find.byType(RichText),
      ),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Container && widget.color == Colors.deepPurple,
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('1 Thessalonians'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    fontSize.dispose();
  });

  testWidgets('phone book buttons follow label length within their columns', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 500,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ViewerBookLabel(
                        label: 'Proverbs',
                        color: Colors.orange,
                        selected: false,
                        fontSize: 22.5,
                        minimumTapHeight: 48,
                        expandWidth: false,
                        onTap: () {},
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ViewerBookLabel(
                        label: 'Ecclesiastes',
                        color: Colors.blue,
                        selected: false,
                        fontSize: 22.5,
                        minimumTapHeight: 48,
                        expandWidth: false,
                        onTap: () {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final shortWidth = tester
        .getSize(
          find.byWidgetPredicate(
            (widget) => widget is Container && widget.color == Colors.orange,
          ),
        )
        .width;
    final longWidth = tester
        .getSize(
          find.byWidgetPredicate(
            (widget) => widget is Container && widget.color == Colors.blue,
          ),
        )
        .width;
    expect(shortWidth, lessThan(longWidth));
    expect(longWidth, lessThanOrEqualTo(244));
    expect(tester.takeException(), isNull);
  });

  testWidgets('larger chapter and verse cells still wrap and select', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: ViewerInlineNumberGrid(
                values: const [1, 10, 100, 176],
                color: Colors.blue,
                fontSize: 30.2,
                minimumItemExtent: 48,
                onSelect: (value) => selected = value,
              ),
            ),
          ),
        ),
      ),
    );

    final cell = find
        .ancestor(of: find.text('176'), matching: find.byType(GestureDetector))
        .first;
    expect(tester.getSize(cell).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(cell).width, greaterThanOrEqualTo(48));
    expect(tester.widget<Text>(find.text('176')).style?.fontSize, 30.2);
    await tester.tap(find.text('176'));
    expect(selected, 176);
    expect(tester.takeException(), isNull);
  });
}
