import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/highlight_render.dart';

void main() {
  group('highlight foreground contrast', () {
    for (final testCase in <({String name, Color color, Color background})>[
      (
        name: 'yellow on dark',
        color: const Color(0xFFFFEB73),
        background: Colors.black,
      ),
      (
        name: 'yellow on light',
        color: const Color(0xFFFFEB73),
        background: Colors.white,
      ),
      (
        name: 'dark blue',
        color: const Color(0xFF173A72),
        background: Colors.white,
      ),
      (
        name: 'medium orange',
        color: const Color(0xFFF28C28),
        background: Colors.white,
      ),
      (
        name: 'custom color',
        color: const Color(0xFF4FAE91),
        background: Colors.white,
      ),
      (
        name: 'translucent on dark',
        color: const Color(0x66FFEB73),
        background: Colors.black,
      ),
      (
        name: 'translucent on light',
        color: const Color(0x66FFEB73),
        background: Colors.white,
      ),
    ]) {
      test(testCase.name, () {
        final spec = resolveHighlightRender(
          testCase.color,
          testCase.background == Colors.black,
          readerBackground: testCase.background,
        );
        expect(
          highlightContrastRatio(spec.backgroundColor, spec.textColor),
          greaterThanOrEqualTo(minimumNormalTextContrastRatio),
        );
      });
    }

    test('light yellow remains light and uses dark text on a dark reader', () {
      final spec = resolveHighlightRender(
        const Color(0xFFFFEB73),
        true,
        readerBackground: Colors.black,
        layerType: HighlightLayerType.savedRange,
      );
      expect(spec.backgroundColor.computeLuminance(), greaterThan(0.35));
      expect(spec.textColor, Colors.black);
    });

    test('source color is not mutated', () {
      const saved = Color(0x7F4FAE91);
      resolveHighlightRender(saved, false, readerBackground: Colors.white);
      expect(saved, const Color(0x7F4FAE91));
    });

    test('semantic color is kept only while accessible', () {
      expect(
        highlightForegroundForBackground(
          Colors.black,
          semanticColor: Colors.red,
        ),
        Colors.red,
      );
      expect(
        highlightForegroundForBackground(
          Colors.yellow,
          semanticColor: Colors.red,
        ),
        Colors.black,
      );
    });
  });
}
