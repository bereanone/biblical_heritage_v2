import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_passage_models.dart';
import 'package:studybible2/features/reader/presentation/viewer_verse_line.dart';

Widget verseRow({
  required bool tagged,
  Brightness brightness = Brightness.light,
  int verse = 8,
  bool chapterStart = false,
  bool marked = false,
  VoidCallback? onNumberTap,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: Scaffold(
    body: ViewerVerseLine(
      line: VerseLine(
        blockId: verse,
        bookNumber: 45,
        chapter: 3,
        verse: verse,
        html: '<w>Scripture text</w>',
        text: 'Scripture text',
      ),
      style: const TextStyle(fontSize: 24),
      isSelected: false,
      isTagged: tagged,
      hasUserMarkup: marked,
      showChapterNumber: chapterStart,
      onTap: () {},
      onVerseNumberTap: onNumberTap,
    ),
  ),
);

bool underlined(WidgetTester tester, String number) =>
    tester
        .widget<Text>(find.text(number))
        .style
        ?.decoration
        ?.contains(TextDecoration.underline) ??
    false;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('tag underline appears and disappears in $brightness', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(verseRow(tagged: false, brightness: brightness));
      expect(underlined(tester, '8'), isFalse);
      await tester.pumpWidget(
        verseRow(
          tagged: true,
          brightness: brightness,
          onNumberTap: () => taps++,
        ),
      );
      await tester.pumpAndSettle();
      expect(underlined(tester, '8'), isTrue);
      await tester.tap(find.text('8'));
      expect(taps, 1);
      await tester.pumpWidget(verseRow(tagged: false, brightness: brightness));
      await tester.pumpAndSettle();
      expect(underlined(tester, '8'), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('tagged verse one keeps chapter heading and its own underline', (
    tester,
  ) async {
    await tester.pumpWidget(
      verseRow(tagged: true, verse: 1, chapterStart: true),
    );
    expect(find.text('3'), findsOneWidget);
    expect(underlined(tester, '3'), isFalse);
    expect(find.text('1'), findsOneWidget);
    expect(underlined(tester, '1'), isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('other markup alone does not claim that a verse is tagged', (
    tester,
  ) async {
    await tester.pumpWidget(verseRow(tagged: false, marked: true));
    expect(underlined(tester, '8'), isFalse);
  });
  testWidgets('three-digit tagged verse fits at enlarged text size', (
    tester,
  ) async {
    await tester.pumpWidget(verseRow(tagged: true, verse: 176));
    expect(underlined(tester, '176'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
