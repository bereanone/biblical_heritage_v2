import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';

void main() {
  group('shouldFallBackToImplicitRoot', () {
    test('falls back on iOS when stored path is dead and has no bookmark', () {
      expect(
        LibraryRootService.shouldFallBackToImplicitRoot(
          isIOS: true,
          storedPath:
              '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/BiblicalHeritage/v2',
          bookmark: null,
          pathExists: false,
        ),
        isTrue,
      );
    });

    test('does not fall back when the stored path still exists', () {
      expect(
        LibraryRootService.shouldFallBackToImplicitRoot(
          isIOS: true,
          storedPath:
              '/var/mobile/Containers/Data/Application/NEW-UUID/Documents/BiblicalHeritage/v2',
          bookmark: null,
          pathExists: true,
        ),
        isFalse,
      );
    });

    test('does not fall back for bookmarked (external) selections', () {
      expect(
        LibraryRootService.shouldFallBackToImplicitRoot(
          isIOS: true,
          storedPath: '/private/var/mobile/External/Folder',
          bookmark: 'bookmark-blob',
          pathExists: false,
        ),
        isFalse,
      );
    });

    test('does not change behavior off iOS', () {
      expect(
        LibraryRootService.shouldFallBackToImplicitRoot(
          isIOS: false,
          storedPath: '/Users/dean/Library/Root',
          bookmark: null,
          pathExists: false,
        ),
        isFalse,
      );
    });

    test('does not fall back when nothing is stored', () {
      expect(
        LibraryRootService.shouldFallBackToImplicitRoot(
          isIOS: true,
          storedPath: '  ',
          bookmark: null,
          pathExists: false,
        ),
        isFalse,
      );
    });
  });

  test('recognizes the app Documents folder as a legacy CloudFiles path', () {
    const documentsPath =
        '/Users/deanbowen/Library/Containers/StudyBible2/Data/Documents';

    expect(
      LibraryRootService.isDefaultAppDocumentsPath(
        candidatePath: documentsPath,
        defaultAppRootPath: documentsPath,
      ),
      isTrue,
    );
    expect(
      LibraryRootService.isDefaultAppDocumentsPath(
        candidatePath: documentsPath,
        defaultAppRootPath: '$documentsPath/CloudFiles',
      ),
      isFalse,
    );
  });
}
