import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/data/epub_download_validator.dart';

Uint8List _zip(Map<String, String> entries) {
  final archive = Archive();
  entries.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

const String _containerXml = '''
<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

String _validOpf({required String title, int chapters = 1}) {
  final manifestItems = StringBuffer();
  final spineItems = StringBuffer();
  for (var i = 0; i < chapters; i++) {
    manifestItems.writeln(
      '<item id="chap$i" href="chap$i.xhtml" media-type="application/xhtml+xml"/>',
    );
    spineItems.writeln('<itemref idref="chap$i"/>');
  }
  return '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
  </metadata>
  <manifest>
    $manifestItems
  </manifest>
  <spine>
    $spineItems
  </spine>
</package>
''';
}

Uint8List _buildValidEpub({
  required String title,
  int chapters = 1,
  String chapterText = 'This is a real chapter with enough readable text.',
}) {
  final entries = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _containerXml,
    'OEBPS/content.opf': _validOpf(title: title, chapters: chapters),
  };
  for (var i = 0; i < chapters; i++) {
    entries['OEBPS/chap$i.xhtml'] =
        '<html><body><p>$chapterText (chapter $i)</p></body></html>';
  }
  return _zip(entries);
}

/// Reproduces the exact shape returned by EGW's media CDN for titles that
/// only have a teaser/stub package: container.xml points at
/// OEBPS/content.opf, but no such entry is actually in the archive.
Uint8List _buildPlaceholderStub({required String title}) {
  return _zip(<String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _containerXml,
    'OEBPS/toc.html':
        '<html><head><title>$title</title></head><body>'
        '<div class="chapter" id="toc"><h3>Table of Contents</h3>'
        '<p><a href="aboutbook.html">Information about this Book</a></p></div>'
        '</body></html>',
  });
}

void main() {
  group('EpubDownloadValidator', () {
    test('accepts a structurally complete EPUB', () {
      final bytes = _buildValidEpub(title: 'The Impending Conflict');
      final result = EpubDownloadValidator.validate(
        bytes,
        expectedTitle: 'The Impending Conflict',
      );
      expect(result.isValid, isTrue);
      expect(result.opfTitle, 'The Impending Conflict');
      expect(result.spineItemCount, 1);
      expect(result.readableContentCount, 1);
    });

    test('rejects an empty response body', () {
      final result = EpubDownloadValidator.validate(Uint8List(0));
      expect(result.isValid, isFalse);
      expect(result.rejectionReason, EpubDownloadRejectionReason.empty);
    });

    test('rejects an HTML error page saved with a .epub extension', () {
      final html = utf8.encode(
        '<html><body><h1>404 Not Found</h1></body></html>',
      );
      final result = EpubDownloadValidator.validate(Uint8List.fromList(html));
      expect(result.isValid, isFalse);
      expect(result.rejectionReason, EpubDownloadRejectionReason.notAZipFile);
    });

    test('rejects a JSON error payload saved with a .epub extension', () {
      final json = utf8.encode('{"error":"not found","status":404}');
      final result = EpubDownloadValidator.validate(Uint8List.fromList(json));
      expect(result.isValid, isFalse);
      expect(result.rejectionReason, EpubDownloadRejectionReason.notAZipFile);
    });

    test('rejects a redirect/login page body (not zip-shaped)', () {
      final html = utf8.encode(
        '<html><head><title>Just a moment...</title></head></html>',
      );
      final result = EpubDownloadValidator.validate(Uint8List.fromList(html));
      expect(result.isValid, isFalse);
      expect(result.rejectionReason, EpubDownloadRejectionReason.notAZipFile);
    });

    test('rejects a truncated/corrupt zip', () {
      final full = _buildValidEpub(title: 'Truncated Book');
      final truncated = full.sublist(0, full.length - 20);
      final result = EpubDownloadValidator.validate(truncated);
      // A truncated zip loses its trailing central directory/EOCD, so the
      // decoder may either throw outright or silently lose one or more
      // entries (commonly whichever was closest to the cut). Either way it
      // must never be accepted as a valid download.
      expect(result.isValid, isFalse);
    });

    test('rejects a zip with no META-INF/container.xml', () {
      final bytes = _zip(<String, String>{
        'mimetype': 'application/epub+zip',
        'OEBPS/content.opf': _validOpf(title: 'No Container'),
      });
      final result = EpubDownloadValidator.validate(bytes);
      expect(result.isValid, isFalse);
      expect(
        result.rejectionReason,
        EpubDownloadRejectionReason.missingContainerXml,
      );
    });

    test('rejects a package whose container.xml points at a missing OPF '
        '(the exact EGW placeholder/teaser shape)', () {
      final bytes = _buildPlaceholderStub(title: 'Christ Our Saviour');
      final result = EpubDownloadValidator.validate(
        bytes,
        expectedTitle: 'Christ Our Saviour',
      );
      expect(result.isValid, isFalse);
      expect(result.rejectionReason, EpubDownloadRejectionReason.missingOpf);
      expect(result.looksLikePlaceholder, isTrue);
    });

    test(
      'the same placeholder shape is rejected regardless of which title it carries '
      '(proves the rule is generic, not a COS/IC special case)',
      () {
        final cos = EpubDownloadValidator.validate(
          _buildPlaceholderStub(title: 'Christ Our Saviour'),
        );
        final ic = EpubDownloadValidator.validate(
          _buildPlaceholderStub(title: 'Impending Conflict'),
        );
        final somethingElse = EpubDownloadValidator.validate(
          _buildPlaceholderStub(title: 'Some Other Title Entirely'),
        );
        for (final result in [cos, ic, somethingElse]) {
          expect(result.isValid, isFalse);
          expect(
            result.rejectionReason,
            EpubDownloadRejectionReason.missingOpf,
          );
        }
      },
    );

    test('rejects an OPF with no manifest items', () {
      final bytes = _zip(<String, String>{
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': _containerXml,
        'OEBPS/content.opf': '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Empty</dc:title></metadata>
  <manifest></manifest>
  <spine></spine>
</package>
''',
      });
      final result = EpubDownloadValidator.validate(bytes);
      expect(result.isValid, isFalse);
      expect(
        result.rejectionReason,
        EpubDownloadRejectionReason.missingManifest,
      );
    });

    test('rejects an OPF with manifest items but no spine', () {
      final bytes = _zip(<String, String>{
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': _containerXml,
        'OEBPS/content.opf': '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>No Spine</dc:title></metadata>
  <manifest>
    <item id="chap0" href="chap0.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine></spine>
</package>
''',
        'OEBPS/chap0.xhtml':
            '<html><body><p>Real content here.</p></body></html>',
      });
      final result = EpubDownloadValidator.validate(bytes);
      expect(result.isValid, isFalse);
      expect(result.rejectionReason, EpubDownloadRejectionReason.missingSpine);
    });

    test(
      'rejects a package whose spine items do not resolve to readable content',
      () {
        final bytes = _zip(<String, String>{
          'mimetype': 'application/epub+zip',
          'META-INF/container.xml': _containerXml,
          'OEBPS/content.opf': _validOpf(title: 'Dangling Spine'),
          // Note: OEBPS/chap0.xhtml deliberately not included.
        });
        final result = EpubDownloadValidator.validate(bytes);
        expect(result.isValid, isFalse);
        expect(
          result.rejectionReason,
          EpubDownloadRejectionReason.noReadableContent,
        );
      },
    );

    test('rejects an EPUB whose title clearly does not match the request', () {
      final bytes = _buildValidEpub(title: 'Steps to Christ');
      final result = EpubDownloadValidator.validate(
        bytes,
        expectedTitle: 'The Impending Conflict',
      );
      expect(result.isValid, isFalse);
      expect(result.rejectionReason, EpubDownloadRejectionReason.titleMismatch);
    });

    test(
      'does not reject a tiny but structurally valid EPUB on size alone',
      () {
        final bytes = _buildValidEpub(
          title: 'Short Tract',
          chapterText: 'Brief but real chapter text.',
        );
        // Sanity: this fixture is deliberately smaller than the size threshold
        // an old size-only rule would have used.
        expect(bytes.length, lessThan(2000));
        final result = EpubDownloadValidator.validate(bytes);
        expect(result.isValid, isTrue);
      },
    );

    test('rejects a placeholder package containing only a two-block '
        'table-of-contents stub (matches the real IC/COS defect shape)', () {
      // This mirrors the real defect: canonical indexing on the raw stub
      // produced exactly two blocks (a heading + one link), because the
      // stub has no OPF/spine at all for the canonicalizer to trust.
      final bytes = _buildPlaceholderStub(title: 'The Impending Conflict');
      final result = EpubDownloadValidator.validate(bytes);
      expect(result.isValid, isFalse);
      expect(result.looksLikePlaceholder, isTrue);
    });

    test('accepts a title match that only differs by punctuation/case', () {
      final bytes = _buildValidEpub(title: 'The Impending Conflict');
      final result = EpubDownloadValidator.validate(
        bytes,
        expectedTitle: 'the impending conflict',
      );
      expect(result.isValid, isTrue);
    });
  });
}
