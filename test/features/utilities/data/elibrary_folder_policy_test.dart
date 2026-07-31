import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:studybible2/features/utilities/data/elibrary_folder_policy.dart';

void main() {
  test(
    'does not treat arbitrary Research or Commentaries folders as managed',
    () {
      expect(
        ELibraryFolderPolicy.isManagedEgwFolderPath(
          p.join('/tmp', 'user', 'Research', 'example.epub'),
        ),
        isFalse,
      );
      expect(
        ELibraryFolderPolicy.isManagedEgwFolderPath(
          p.join('/tmp', 'user', 'Commentaries', 'example.pdf'),
        ),
        isFalse,
      );
    },
  );

  test(
    'recognizes the dedicated raw-Pioneer-EPUB-folder-import managed folder',
    () {
      expect(
        ELibraryFolderPolicy.isPioneerImportedEpubFolderPath(
          p.join('/tmp', 'root', 'ImportedPioneerEpubs', 'book_abc123.epub'),
        ),
        isTrue,
      );
      expect(
        ELibraryFolderPolicy.isPioneerImportedEpubFolderPath(
          p.join('/tmp', 'root', 'ePubs', 'MyBooks', 'book.epub'),
        ),
        isFalse,
      );
    },
  );

  test('treats actual managed EGW folders as managed', () {
    expect(
      ELibraryFolderPolicy.isManagedEgwFolderPath(
        p.join('/tmp', 'root', 'ePubs', 'EGW', 'EGW_Books', 'en_1T.epub'),
      ),
      isTrue,
    );
    expect(
      ELibraryFolderPolicy.isManagedEgwFolderPath(
        p.join('/tmp', 'root', 'PDFs', 'EGW', 'EGW_Commentaries', 'en_1T.pdf'),
      ),
      isTrue,
    );
  });
}
