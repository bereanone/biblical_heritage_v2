import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:studybible2/features/library/data/library_epub_metadata.dart';

Uint8List _epubBytes(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const String _containerXml = '''
<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

Uint8List _epubWithMetadata({required String title, required String creator}) {
  final opf =
      '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    <dc:creator>$creator</dc:creator>
  </metadata>
</package>
''';
  return _epubBytes(<String, List<int>>{
    'mimetype': 'application/epub+zip'.codeUnits,
    'META-INF/container.xml': _containerXml.codeUnits,
    'OEBPS/content.opf': opf.codeUnits,
  });
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('epub_metadata_');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<LibraryEpubMetadata?> readFor(String title, String creator) async {
    final file = File(p.join(directory.path, 'book.epub'));
    await file.writeAsBytes(
      _epubWithMetadata(title: title, creator: creator),
      flush: true,
    );
    return readLibraryEpubMetadata(file);
  }

  test('decodes &quot; in title', () async {
    final metadata = await readFor('The &quot;Marvel&quot; of Nations', 'A');
    expect(metadata!.title, 'The "Marvel" of Nations');
  });

  test('decodes &amp; in creator', () async {
    final metadata = await readFor('T', 'Smith &amp; Jones');
    expect(metadata!.creator, 'Smith & Jones');
  });

  test('decodes &#13; decimal numeric reference', () async {
    final metadata = await readFor('Line One&#13;Line Two', 'A');
    expect(metadata!.title, 'Line One\rLine Two');
  });

  test('decodes decimal numeric references, e.g. &#39;', () async {
    final metadata = await readFor('Believer&#39;s Guide', 'A');
    expect(metadata!.title, "Believer's Guide");
  });

  test('decodes hexadecimal numeric references, e.g. &#x27;', () async {
    final metadata = await readFor('Believer&#x27;s Guide', 'A');
    expect(metadata!.title, "Believer's Guide");
  });
}
