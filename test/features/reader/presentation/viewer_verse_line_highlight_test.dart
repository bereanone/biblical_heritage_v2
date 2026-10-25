import 'package:flutter/material.dart';
import 'package:studybible2/features/reader/presentation/text_range_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/data/highlights_repository.dart';
import 'package:studybible2/features/reader/presentation/highlight_render.dart';
import 'package:studybible2/features/reader/presentation/viewer_passage_models.dart';
import 'package:studybible2/features/reader/presentation/viewer_verse_line.dart';

void main() {
  testWidgets('verse reports actual token endpoints for selection handles', (tester) async {
    final registry = TextRangeGeometryRegistry();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ViewerVerseLine(
      line: const VerseLine(blockId: 9, bookNumber: 27, chapter: 7, verse: 20,
        html: '<w>the</w> <w>horns that were</w> <w>in</w>', text: 'the horns that were in'),
      style: const TextStyle(fontSize: 20), isSelected: false,
      geometryRegistry: registry, onTap: () {},
    ))));
    await tester.pump();
    expect(registry.entries.length, 3);
    for (final entry in registry.entries) {
      expect(entry.anchor.blockId, 9);
      expect(entry.globalRect.width, greaterThan(0));
      expect(entry.globalStartRect, isNotNull);
      expect(entry.globalEndRect, isNotNull);
    }
    await tester.pumpWidget(const SizedBox());
    registry.dispose();
  });
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
  for (final brightness in Brightness.values) {
    testWidgets('selected red-letter verse stays readable in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: ViewerVerseLine(
              line: const VerseLine(
                blockId: 1,
                bookNumber: 66,
                chapter: 1,
                verse: 11,
                html: '<w>I am Alpha</w>',
                text: 'I am Alpha',
              ),
              style: const TextStyle(fontSize: 20),
              isSelected: true,
              startsInRedLetter: true,
              highlight: const VerseHighlightRecord(
                id: 1,
                groupId: 1,
                verseRef: 'Revelation 1:11',
                colorHex: '#FFE34D',
              ),
              onTap: () {},
            ),
          ),
        ),
      );
      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final background = (container.decoration! as BoxDecoration).color!;
      final rich = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((w) => w.text.toPlainText().contains('I am Alpha'));
      final colors = <Color>[];
      void collect(InlineSpan span) {
        if (span.style?.color case final Color color) colors.add(color);
        if (span is TextSpan)
          for (final child in span.children ?? <InlineSpan>[]) {
            collect(child);
          }
      }

      collect(rich.text);
      expect(colors, isNotEmpty);
      expect(colors.any((c) => c.r > c.g && c.r > c.b), isTrue);
      for (final color in colors) {
        expect(
          highlightContrastRatio(background, color),
          greaterThanOrEqualTo(4.5),
        );
      }
      final number = tester.widget<Text>(find.text('11'));
      expect(
        highlightContrastRatio(background, number.style!.color!),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}
