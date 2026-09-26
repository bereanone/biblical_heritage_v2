import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_book_reader_screen.dart';

void main() {
  test(
    'legacy citations preserve exact text and emphasis across styled runs',
    () {
      final recognizers = <String, TapGestureRecognizer>{};
      final input = <InlineSpan>[
        const TextSpan(text: 'Holy Spirit. Psalm '),
        const TextSpan(
          text: '139:7',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
        const TextSpan(text: '. {FP1872 4.2}'),
      ];
      final output = linkLibraryReaderSpans(
        input,
        (href) => recognizers.putIfAbsent(href, TapGestureRecognizer.new),
      );
      expect(
        TextSpan(children: output).toPlainText(),
        TextSpan(children: input).toPlainText(),
      );
      expect(recognizers.keys.single, 'studybible-citation:Psalm%20139%3A7');
      final linked = output
          .cast<TextSpan>()
          .where((s) => s.recognizer != null)
          .toList();
      expect(linked.map((s) => s.text).join(), 'Psalm 139:7');
      expect(linked.last.style!.fontStyle, FontStyle.italic);
      for (final recognizer in recognizers.values) {
        recognizer.dispose();
      }
    },
  );

  testWidgets('legacy inline verse tap reaches the shared popup action', (
    tester,
  ) async {
    String? target;
    final recognizer = TapGestureRecognizer()
      ..onTap = () => target = 'Psalm 139:7';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Text.rich(
            TextSpan(
              children: linkLibraryReaderSpans(const [
                TextSpan(text: 'Psalm 139:7.'),
              ], (_) => recognizer),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(RichText).first);
    expect(target, 'Psalm 139:7');
    await tester.pumpWidget(const SizedBox());
    recognizer.dispose();
  });
}
