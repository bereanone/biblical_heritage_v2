import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_xml_html_entities.dart';

void main() {
  group('decodeXmlHtmlEntities', () {
    test('decodes the five predefined XML entities', () {
      expect(decodeXmlHtmlEntities('&amp;'), '&');
      expect(decodeXmlHtmlEntities('&lt;'), '<');
      expect(decodeXmlHtmlEntities('&gt;'), '>');
      expect(decodeXmlHtmlEntities('&quot;'), '"');
      expect(decodeXmlHtmlEntities('&apos;'), "'");
    });

    test('decodes &nbsp; to a plain space', () {
      expect(decodeXmlHtmlEntities('a&nbsp;b'), 'a b');
    });

    test('decodes decimal numeric references', () {
      expect(decodeXmlHtmlEntities('&#39;'), "'");
      expect(decodeXmlHtmlEntities('&#13;'), '\r');
    });

    test('decodes hex numeric references, either case', () {
      expect(decodeXmlHtmlEntities('&#x27;'), "'");
      expect(decodeXmlHtmlEntities('&#X27;'), "'");
    });

    test('does not double-unescape &amp;amp;', () {
      expect(decodeXmlHtmlEntities('&amp;amp;'), '&amp;');
    });

    test('leaves unknown or malformed entities unchanged', () {
      expect(decodeXmlHtmlEntities('&foo;'), '&foo;');
      expect(decodeXmlHtmlEntities('&amp'), '&amp');
      expect(decodeXmlHtmlEntities('a & b'), 'a & b');
    });

    test('decodes multiple entities in one string', () {
      expect(
        decodeXmlHtmlEntities('Smith &amp; Jones &quot;Marvel&quot;'),
        'Smith & Jones "Marvel"',
      );
    });
  });
}
