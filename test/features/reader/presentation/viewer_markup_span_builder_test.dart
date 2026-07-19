import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_markup_span_builder.dart';
import 'package:studybible2/features/reader/data/highlights_repository.dart';

void main() {
  test('keeps trailing punctuation attached to the preceding token', () {
    final segments = parseViewerMarkupSegments(
      html:
          '<w lemma="strong:G562">Surely</w>, <w lemma="strong:G2316">God</w>.',
      fallbackText: 'Surely, God.',
      baseStyle: const TextStyle(),
      redLetterColor: Colors.red,
    );

    expect(segments.map((segment) => segment.text).toList(), [
      'Surely',
      ', ',
      'God',
      '.',
    ]);
    expect(segments.map((segment) => segment.tokenIndex).toList(), [
      1,
      1,
      2,
      2,
    ]);
  });

  test('highlighted Bible markup keeps italics and overrides unsafe red', () {
    final span =
        buildViewerMarkupSpan(
              html: '<w><i><span class="wj">Words</span></i></w>',
              fallbackText: 'Words',
              baseStyle: const TextStyle(color: Colors.white),
              redLetterColor: Colors.red,
              isNightMode: true,
              persistedHighlights: const [
                VerseHighlightRecord(
                  id: 1,
                  groupId: 1,
                  verseRef: 'John 1:1',
                  colorHex: '#FFEB73',
                  startToken: 1,
                  endToken: 1,
                ),
              ],
            )
            as TextSpan;

    final highlighted = span.children!.first as TextSpan;
    expect(highlighted.style!.fontStyle, FontStyle.italic);
    expect(highlighted.style!.backgroundColor, isNotNull);
    expect(highlighted.style!.color, Colors.black);
  });

  test('unhighlighted Bible text keeps its original styling', () {
    const base = TextStyle(color: Colors.white);
    final span =
        buildViewerMarkupSpan(
              html: '<w><i>Words</i></w>',
              fallbackText: 'Words',
              baseStyle: base,
              redLetterColor: Colors.red,
              isNightMode: true,
            )
            as TextSpan;

    final text = span.children!.first as TextSpan;
    expect(text.style!.color, Colors.white);
    expect(text.style!.fontStyle, FontStyle.italic);
    expect(text.style!.backgroundColor, isNull);
  });
}
