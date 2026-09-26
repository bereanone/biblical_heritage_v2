import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_epub_text_styles.dart';

void main() {
  test('compact vertical margins follow shorthand, cascade and overrides', () {
    final styles = EpubTextStyles.read('<style>p {margin:0px;} .spaced {margin:1em 0;} .fixed {margin-bottom:0!important;}</style>', 'chapter.xhtml', null);
    expect(styles.hasCompactVerticalMargins('p', ''), isTrue);
    expect(styles.hasCompactVerticalMargins('p', 'class="spaced"'), isFalse);
    expect(styles.hasCompactVerticalMargins('p', 'style="margin:0 2em 0 2em"'), isTrue);
    expect(styles.hasCompactVerticalMargins('p', 'style="margin:0 0 1em"'), isFalse);
    expect(styles.hasCompactVerticalMargins('p', 'class="fixed" style="margin-bottom:2em"'), isTrue);
    expect(styles.hasCompactVerticalMargins('p', 'style="margin-top:.8333%"'), isTrue);
    expect(styles.hasCompactVerticalMargins('p', 'style="margin-top:2%"'), isFalse);
    expect(styles.resolve('p', ''), isEmpty);
  });
  test(
    'relative size follows cascade and does not become an emphasis mark',
    () {
      final styles = EpubTextStyles.read(
        '<style>h1 {font-size:150%;}'
            '.stanza {font-size:75%;} .note {font-size:.8em!important;}'
            '</style>',
        'chapter.xhtml',
        null,
      );
      expect(styles.resolveFontScale('h1', 'class="stanza"'), .75);
      expect(
        styles.resolveFontScale('h1', 'class="stanza" style="font-size:100%"'),
        1,
      );
      expect(
        styles.resolveFontScale('p', 'class="note" style="font-size:120%"'),
        .8,
      );
      expect(
        styles.resolveFontScale(
          'p',
          'class="note" style="font-size:120%!important"',
        ),
        1.2,
      );
      expect(styles.resolveFontScale('h1', 'style="font-size:20px"'), isNull);
      expect(styles.resolveFontScale('p', 'style="font-size:.1em"'), .7);
      expect(styles.resolve('h1', 'class="stanza"'), isEmpty);
    },
  );
  test(
    'alignment uses CSS cascade without leaking alignment into text marks',
    () {
      final styles = EpubTextStyles.read(
        '<style>'
            '.poem {text-align:center;font-style:italic;}'
            'p.poem {text-align:right;}'
            '#title {text-align:center!important;}'
            '@media print {p {text-align:left;}}'
            '</style>',
        'chapter.xhtml',
        null,
      );
      expect(styles.resolveAlignment('div', 'class="poem"'), 'center');
      expect(styles.resolveAlignment('p', 'class="poem"'), 'right');
      expect(
        styles.resolveAlignment('p', 'class="poem" style="text-align:left"'),
        'left',
      );
      expect(
        styles.resolveAlignment('p', 'id="title" style="text-align:right"'),
        'center',
      );
      expect(styles.resolveAlignment('p', ''), isNull);
      expect(styles.resolve('p', 'class="poem"'), {'italic': true});
    },
  );
  test(
    'uses the linked stylesheet with selector specificity and normal resets',
    () {
      final archive = Archive();
      void css(String path, String content) {
        final bytes = utf8.encode(content);
        archive.addFile(ArchiveFile(path, bytes.length, bytes));
      }

      css(
        'OEBPS/css/book style.css',
        '@font-face { font-style: italic; }'
            '@media print { span { font-weight: bold; } }'
            'span.Italic { font-style: italic; font-weight: normal; }'
            '.Bold {font-weight: bold;}'
            'span.Bold {font-weight: 700;}'
            '.Bold {font-weight:normal;}'
            '.Italic.reset {font-style:normal;}'
            '#special {font-style:italic!important;}',
      );
      css('OEBPS/unlinked.css', 'span {font-weight:bold;font-style:italic;}');
      final styles = EpubTextStyles.read(
        '<link rel="stylesheet" href="css/book%20style.css"/>',
        'OEBPS/content.xhtml',
        archive,
      );
      expect(
        styles.resolve('span', 'class="Italic"', inherited: {'bold': true}),
        {'italic': true, 'bold': false},
      );
      expect(styles.resolve('span', 'class="Bold"')['bold'], isTrue);
      expect(styles.resolve('span', 'class="Italic reset"')['italic'], isFalse);
      expect(styles.resolve('span', 'class="italic"'), isEmpty);
      expect(styles.resolve('span', ''), isEmpty);
      expect(
        styles.resolve(
          'span',
          'id="special" style="font-style:normal"',
        )['italic'],
        isTrue,
      );
      expect(
        styles.resolve(
          'span',
          'id="special" style="font-style:normal!important"',
        )['italic'],
        isFalse,
      );
      expect(
        styles.resolve('span', 'style="font-weight:650;font-style:oblique"'),
        {'bold': true, 'italic': true},
      );
    },
  );
}
