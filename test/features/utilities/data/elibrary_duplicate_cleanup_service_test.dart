import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/data/elibrary_duplicate_cleanup_service.dart';

void main() {
  test('duplicate cleanup candidates include EPUB and PDF files', () {
    expect(isElibraryDuplicateCandidateFilePath('/tmp/book.epub'), isTrue);
    expect(isElibraryDuplicateCandidateFilePath('/tmp/book.pdf'), isTrue);
    expect(isElibraryDuplicateCandidateFilePath('/tmp/book.txt'), isFalse);
  });
}
