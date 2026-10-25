import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_passage_models.dart';
import 'package:studybible2/features/reader/presentation/viewer_verse_line.dart';

Widget readerRow(int chapter, int verse, {VoidCallback? onNumberTap}) {
  return MaterialApp(
    home: Scaffold(
      body: ViewerVerseLine(
        line: VerseLine(
          blockId: verse,
          bookNumber: 45,
          chapter: chapter,
          verse: verse,
          html: '<w>Scripture text</w>',
          text: 'Scripture text',
        ),
        style: const TextStyle(fontSize: 20),
        isSelected: false,
        // Reproduce the caller's chapter-start fallback when its preceding
        // row context is missing. The verse must defend its own identity.
        showChapterNumber: true,
        onTap: () {},
        onVerseNumberTap: onNumberTap,
      ),
    ),
  );
}

void main() {
  for (final verse in [8, 9, 10, 11, 12]) {
    testWidgets('Romans 3:$verse retains its number despite missing context', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(readerRow(3, verse, onNumberTap: () => taps++));
      expect(find.text('$verse'), findsOneWidget);
      expect(find.text('3'), findsNothing);
      await tester.tap(find.text('$verse'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('chapter starts retain the large chapter label', (tester) async {
    await tester.pumpWidget(readerRow(3, 1));
    expect(find.text('3'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('3')).style!.fontSize,
      greaterThan(20),
    );
    expect(find.text('1'), findsNothing);
  });

  testWidgets('rebuilding through chapter jumps preserves verse identity', (
    tester,
  ) async {
    for (final location in [(3, 8), (4, 1), (4, 2), (3, 9), (119, 176)]) {
      final (chapter, verse) = location;
      await tester.pumpWidget(readerRow(chapter, verse));
      await tester.pump();
      expect(find.text('${verse == 1 ? chapter : verse}'), findsOneWidget);
      if (verse != 1) expect(find.text('$chapter'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
