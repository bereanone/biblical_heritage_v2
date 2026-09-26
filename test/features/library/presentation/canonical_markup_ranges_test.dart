import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/elibrary_markup_repository.dart';
import 'package:studybible2/features/library/data/library_document_models.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';

void main() {
  ElibraryMarkupRecord mark(int start, int end, String text, String kind) =>
      ElibraryMarkupRecord(
        id: start + 1,
        libraryItemId: 'book',
        epubHref: 'canonical:block',
        startBlockIndex: 0,
        startCharOffset: start,
        endBlockIndex: 0,
        endCharOffset: end,
        selectedTextSnapshot: text,
        markupType: kind,
        color: '#00FF00',
        createdAt: '',
        updatedAt: '',
      );
  LibraryDocumentBlock block(LibraryFormattedContent formatted) =>
      LibraryDocumentBlock(
        id: 'block',
        libraryItemId: 'book',
        sectionId: 'section',
        displayOrder: 0,
        blockType: LibraryDocumentBlockType.paragraph,
        plainText: 'One two three.',
        formattedContent: formatted.toJson(),
        contentHash: 'hash',
      );
  test('inline citations remain proportionally smaller at reader font sizes', () {
    const formatted = LibraryFormattedContent(nodes: [
      {'type':'text','text':'One '},
      {'type':'text','text':'two','relative_font_scale':.85},
      {'type':'text','text':' three.'},
    ]);
    for (final size in [18.0, 27.0]) {
      final spans = canonicalInlineTextSpans(block:block(formatted), formatted:formatted,
        bodyStyle:TextStyle(fontSize:size), referenceStyle:const TextStyle(),
        showReferenceCode:false).cast<TextSpan>();
      expect(spans.elementAt(1).style?.fontSize, closeTo(size*.85,.001));
      expect(spans.first.style?.fontSize, size);
      expect(TextSpan(children:spans.toList()).toPlainText(),'One two three.');
    }
  });
  test(
    'highlight spans only the selected words across source formatting boundaries',
    () {
      const formatted = LibraryFormattedContent(
        nodes: [
          {'type': 'text', 'text': 'One '},
          {
            'type': 'text',
            'text': 'two',
            'marks': ['italic'],
          },
          {'type': 'text', 'text': ' three.'},
        ],
      );
      final spans = canonicalInlineTextSpans(
        block: block(formatted),
        formatted: formatted,
        bodyStyle: const TextStyle(),
        referenceStyle: const TextStyle(),
        showReferenceCode: false,
        markups: [mark(4, 13, 'two three', 'highlight')],
      );
      expect(TextSpan(children: spans).toPlainText(), 'One two three.');
      final texts = spans.cast<TextSpan>();
      expect(texts.first.style?.backgroundColor, isNull);
      expect(texts.last.text, '.');
      expect(texts.last.style?.backgroundColor, isNull);
      expect(
        texts.firstWhere((s) => s.text == 'two').style?.fontStyle,
        FontStyle.italic,
      );
      expect(
        texts
            .where((s) => s.style?.backgroundColor != null)
            .map((s) => s.text)
            .join(),
        'two three',
      );
    },
  );
  test(
    'underline and highlight coexist and stale selections are not misplaced',
    () {
      final formatted = LibraryFormattedContent.plain('One two three.');
      final spans = canonicalInlineTextSpans(
        block: block(formatted),
        formatted: formatted,
        bodyStyle: const TextStyle(),
        referenceStyle: const TextStyle(),
        showReferenceCode: false,
        markups: [
          mark(4, 7, 'two', 'underline'),
          mark(4, 7, 'two', 'highlight'),
          mark(0, 3, 'OLD', 'highlight'),
        ],
      ).cast<TextSpan>();
      final two = spans.firstWhere((s) => s.text == 'two');
      expect(two.style?.decoration, TextDecoration.underline);
      expect(two.style?.backgroundColor, const Color(0xFF00FF00));
      expect(spans.first.style?.backgroundColor, isNull);
    },
  );
}
