import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_source_type.dart';

void main() {
  List<int> zip(Map<String, String> files) {
    final archive = Archive();
    files.forEach((name, text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return ZipEncoder().encode(archive);
  }

  test('legacy provider suffix is moved before the effective extension', () {
    expect(
      normalizedEpubFileName('Appeal on Immortality.epub.1787941785930447'),
      'Appeal on Immortality.1787941785930447.epub',
    );
    expect(normalizedEpubFileName('Book.EPUB.123'), 'Book.123.epub');
    expect(normalizedEpubFileName('book.epub'), 'book.epub');
  });
  test('metadata and legacy names identify EPUB for structural validation', () {
    expect(librarySourceIsEpub([], path: 'book.epub.123'), isTrue);
    expect(
      librarySourceIsEpub([], path: 'cached', originalName: 'book.epub'),
      isTrue,
    );
    expect(
      librarySourceIsEpub([], path: 'cached', mimeType: 'application/epub+zip'),
      isTrue,
    );
  });
  test('content identifies EPUB even under an HTML or extensionless name', () {
    expect(
      librarySourceIsEpub(
        zip({'mimetype': 'application/epub+zip'}),
        path: 'wrong.html',
      ),
      isTrue,
    );
    expect(
      librarySourceIsEpub(
        zip({'META-INF/container.xml': '<container/>'}),
        path: 'cache',
      ),
      isTrue,
    );
  });
  test('non-EPUB ZIP cannot fall through to the text renderer', () {
    expect(
      () => librarySourceIsEpub(zip({'book.txt': 'text'}), path: 'wrong.html'),
      throwsFormatException,
    );
    expect(
      librarySourceIsEpub(utf8.encode('<p>Text</p>'), path: 'book.html'),
      isFalse,
    );
  });
}
