import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/data/highlights_repository.dart';
import 'package:studybible2/features/reader/presentation/highlight_render.dart';
import 'package:studybible2/features/reader/presentation/viewer_passage_models.dart';
import 'package:studybible2/features/reader/presentation/viewer_verse_line.dart';

void main() {
  testWidgets('dark reader renders a saved yellow token range with dark text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
        home: Scaffold(
          body: ViewerVerseLine(
            line: const VerseLine(
              blockId: 1,
              bookNumber: 48,
              chapter: 4,
              verse: 19,
              html: '<w>My</w> <w>little</w> <w>children</w>',
              text: 'My little children',
            ),
            style: const TextStyle(color: Colors.white, fontSize: 20),
            isSelected: false,
            tokenHighlights: const [
              VerseHighlightRecord(
                id: 1,
                groupId: 1,
                verseRef: 'Galatians 4:19',
                colorHex: '#FFE34D',
                startToken: 1,
                endToken: 3,
              ),
            ],
            onTap: () {},
          ),
        ),
      ),
    );

    final richText = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere(
          (widget) => widget.text.toPlainText().contains('My little children'),
        );
    final root = richText.text as TextSpan;
    final body = root.children!.single as TextSpan;
    final highlighted = body.children!.whereType<TextSpan>().where(
      (span) => span.style?.backgroundColor != null,
    );

    expect(highlighted, isNotEmpty);
    for (final span in highlighted) {
      expect(span.style!.color, Colors.black);
      expect(
        highlightContrastRatio(
          span.style!.backgroundColor!,
          span.style!.color!,
        ),
        greaterThanOrEqualTo(minimumNormalTextContrastRatio),
      );
    }
  });
}
