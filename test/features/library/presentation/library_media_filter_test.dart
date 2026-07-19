import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_media_filter.dart';

void main() {
  test('fresh and absent preferences default to All', () {
    expect(normalizeLibraryMediaFilter(null), libraryMediaFilterAll);
    expect(normalizeLibraryMediaFilter(''), libraryMediaFilterAll);
  });

  test('invalid and stale preferences fall back to All', () {
    expect(normalizeLibraryMediaFilter('video'), libraryMediaFilterAll);
    expect(
      normalizeLibraryMediaFilter('legacy-epub-default'),
      libraryMediaFilterAll,
    );
  });

  test('explicit PDF and ePub preferences restore canonically', () {
    expect(normalizeLibraryMediaFilter('pdfs'), 'PDFs');
    expect(normalizeLibraryMediaFilter('ePubs'), 'ePubs');
  });
}
