import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_markup_span_builder.dart';

void main() {
  test('keeps trailing punctuation attached to the preceding token', () {
    final segments = parseViewerMarkupSegments(
      html: '<w lemma="strong:G562">Surely</w>, <w lemma="strong:G2316">God</w>.',
      fallbackText: 'Surely, God.',
      baseStyle: const TextStyle(),
      redLetterColor: Colors.red,
    );

    expect(
      segments.map((segment) => segment.text).toList(),
      ['Surely', ', ', 'God', '.'],
    );
    expect(
      segments.map((segment) => segment.tokenIndex).toList(),
      [1, 1, 2, 2],
    );
  });
}
