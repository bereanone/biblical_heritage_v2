import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/epub_text_flow.dart';

void main() {
  test('browser-wrapped prose lines collapse into one paragraph', () {
    expect(
      normalizeEpubInlineTextFlow(
        '<p>Browser wrapped\nprose<br/>continues</p>',
      ),
      '<p>Browser wrapped prose continues</p>',
    );
  });

  test('single soft br in ordinary prose becomes a space', () {
    expect(
      normalizeEpubInlineTextFlow('<p>one line<br>next line</p>'),
      '<p>one line next line</p>',
    );
  });

  test('repeated hard breaks create a real paragraph boundary', () {
    expect(
      normalizeEpubInlineTextFlow('<p>first<br/><br/>second</p>'),
      '<p>first\n\nsecond</p>',
    );
  });

  test('normal p boundaries and headings remain separate', () {
    const html = '<h2>Chapter</h2><p>First</p><p>Second</p>';
    expect(normalizeEpubInlineTextFlow(html), html);
  });

  test('intentional long poem preserves line breaks', () {
    const html =
        '<p class="poem-noindent">Line one:<br/>Line two;<br/>Line three.<br/>Line four:<br/>Line five;<br/>Line six.<br/>Line seven.</p>';
    final normalized = normalizeEpubInlineTextFlow(html);
    expect('\n'.allMatches(normalized).length, 6);
    expect(normalized, isNot(contains('<br')));
  });

  test('lists and tables preserve structured line breaks', () {
    expect(
      normalizeEpubInlineTextFlow('<li>first<br/>continuation</li>'),
      '<li>first\ncontinuation</li>',
    );
    expect(
      normalizeEpubInlineTextFlow('<td>first<br/>second</td>'),
      '<td>first\nsecond</td>',
    );
  });

  test('reference marker remains in its owning paragraph', () {
    const html =
        '<p>quoted<br/>text <span class="refcode">{SC 25.1}</span></p>';
    expect(
      normalizeEpubInlineTextFlow(html),
      '<p>quoted text <span class="refcode">{SC 25.1}</span></p>',
    );
  });

  test('empty break runs do not generate spacer blocks', () {
    final normalized = normalizeEpubInlineTextFlow(
      '<p>first<br/><br/>second</p>',
    );
    expect(normalized, isNot(contains('<br')));
    expect(normalized.split('\n\n'), hasLength(2));
  });

  test('exact Steps to Christ SC 25.1 quotation flows cleanly', () {
    const html =
        '<p class="poem-noindent">“Blessed is he whose transgression is forgiven,\n'
        '<br/>whose sin is covered.\n'
        '<br/>Blessed is the man unto whom the Lord\n'
        '<br/>imputeth not iniquity,\n'
        '<br/>And in whose spirit there is no guile.”</p>';
    expect(
      normalizeEpubInlineTextFlow(html),
      '<p class="poem-noindent">“Blessed is he whose transgression is forgiven, '
      'whose sin is covered. Blessed is the man unto whom the Lord '
      'imputeth not iniquity, And in whose spirit there is no guile.”</p>',
    );
  });

  test('clean stored paragraph is not split by continuous rendering', () {
    const html =
        '<p>“Blessed is he whose transgression is forgiven, whose sin is covered.”</p>';
    expect(normalizeEpubInlineTextFlow(html), html);
  });
}
