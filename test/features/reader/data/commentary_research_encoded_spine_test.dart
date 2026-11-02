import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/data/commentary_research_library_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('URI-encoded spine paths retain main text after an introduction', () async {
    final directory = await Directory.systemTemp.createTemp('encoded-spine-');
    addTearDown(() => directory.delete(recursive: true));
    final archive = Archive();
    final entries = <String, String>{
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
      'OEBPS/content.opf':
          '<package><manifest><item id="intro" href="intro.xhtml"/><item id="body" href="Book%20%28main%29.xhtml"/></manifest><spine><itemref idref="intro"/><itemref idref="body"/></spine></package>',
      'OEBPS/intro.xhtml':
          '<html><head><title>Introduction</title></head><body><h1>Introduction</h1><p>An introduction that must not hide the following chapter.</p></body></html>',
      'OEBPS/Book (main).xhtml':
          '<html><head><title>Living by Faith</title></head><body><h1>Living by Faith</h1><p>The complete main text remains available in the book reader.</p></body></html>',
    };
    for (final entry in entries.entries) {
      final bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    final file = File('${directory.path}/book.epub');
    await file.writeAsBytes(ZipEncoder().encode(archive));
    final sections = await CommentaryResearchLibraryService.instance
        .loadBookSectionsFromEpubFile(
          file: file,
          libraryItemId: 'encoded-spine',
        );
    final text = sections.expand((s) => s.blocks).map((b) => b.text).join('\n');
    expect(text, contains('An introduction that must not hide'));
    expect(text, contains('The complete main text remains available'));
    expect(
      text.indexOf('An introduction'),
      lessThan(text.indexOf('The complete main')),
    );
  });
}
