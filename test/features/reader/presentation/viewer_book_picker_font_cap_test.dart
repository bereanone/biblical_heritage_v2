import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_book_label.dart';

void main() {
  const names = ['James', 'Psalms', 'Song of Solomon', '2 Thessalonians'];
  for (final phoneWidth in [320.0, 390.0, 430.0]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('one-line book labels at width $phoneWidth and scale $scale', (tester) async {
        final column = (phoneWidth * .92 - 48) / 2;
        final size = fitBookPickerFontSize(labels: names,
          requestedSize: 30.2 * scale, availableTextWidth: column - 16,
          baseStyle: ThemeData().textTheme.bodyMedium!,
          textDirection: TextDirection.ltr);
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.noScaling),
          child: Scaffold(body: Center(child: SizedBox(width: column,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final name in names) ViewerBookLabel(label: name,
                color: Colors.blue, selected: true, onTap: () {},
                fontSize: size, minimumTapHeight: 48, singleLine: true),
            ]),
          ))),
        )));
        for (final name in names) {
          final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
            of: find.widgetWithText(ViewerBookLabel, name), matching: find.byType(RichText)));
          expect(paragraph.didExceedMaxLines, isFalse, reason: name);
          final painter = TextPainter(text: paragraph.text, textDirection: TextDirection.ltr)..layout(maxWidth: paragraph.size.width);
          expect(painter.computeLineMetrics().length, 1, reason: name);
          painter.dispose();
          expect(tester.getSize(find.widgetWithText(ViewerBookLabel, name)).height, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  test('picker grows until its width limit, then stops', () {
    double fit(double requested) => fitBookPickerFontSize(labels: names,
      requestedSize: requested, availableTextWidth: 170, textDirection: TextDirection.ltr);
    expect(fit(10), 10);
    expect(fit(9), 9);
    expect(fit(80), closeTo(fit(160), 0.01));
    expect(fit(80), lessThan(80));
  });
}
