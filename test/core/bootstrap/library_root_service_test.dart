import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';

void main() {
  group('iOS app-managed library continuity', () {
    late Directory documents;
    setUp(() async {
      documents = await Directory.systemTemp.createTemp(
        'library-root-continuity-',
      );
    });
    tearDown(() async {
      await documents.delete(recursive: true);
    });
    String resolve({bool isIOS = true}) =>
        LibraryRootService.resolveDefaultAppLibraryRoot(
          documentsPath: documents.path,
          isIOS: isIOS,
        );
    Future<void> databaseAt(String root, String name) async {
      final file = File(p.join(root, name));
      await file.parent.create(recursive: true);
      await file.writeAsString('SQLite format 3');
    }

    test(
      'recognizes books initialized after a first empty-root lookup',
      () async {
        expect(resolve(), documents.path);
        final existing = p.join(documents.path, 'BiblicalHeritage', 'v2');
        await databaseAt(existing, 'user.db');
        await databaseAt(existing, 'eLibrary.db');
        expect(resolve(), existing);
        expect(resolve(isIOS: false), documents.path);
      },
    );
    test(
      'does not abandon a Documents database for an older child library',
      () async {
        final existing = p.join(documents.path, 'BiblicalHeritage', 'v2');
        await databaseAt(existing, 'user.db');
        await databaseAt(p.join(documents.path, 'Databases'), 'eLibrary.db');
        expect(resolve(), documents.path);
      },
    );
    test('preserves legacy databases directly under Documents', () async {
      await databaseAt(
        p.join(documents.path, 'BiblicalHeritage', 'v2'),
        'user.db',
      );
      await databaseAt(documents.path, 'user.db');
      expect(resolve(), documents.path);
    });
    test('repairs only the empty parent app-folder selection', () async {
      final existing = p.join(documents.path, 'BiblicalHeritage', 'v2');
      await databaseAt(existing, 'user.db');
      bool repair({
        LibraryRootSource source = LibraryRootSource.defaultAppFolder,
        String? bookmark,
        bool isIOS = true,
        String? path,
      }) => LibraryRootService.shouldRecoverDefaultAppSelection(
        isIOS: isIOS,
        source: source,
        bookmark: bookmark,
        storedPath: path ?? documents.path,
        documentsPath: documents.path,
        defaultRoot: resolve(),
      );
      expect(repair(), isTrue);
      expect(repair(source: LibraryRootSource.userSelected), isFalse);
      expect(repair(bookmark: 'external-access'), isFalse);
      expect(repair(isIOS: false), isFalse);
      expect(repair(path: p.join(documents.path, 'another-folder')), isFalse);
      await databaseAt(p.join(documents.path, 'Databases'), 'user.db');
      expect(repair(), isFalse);
    });
  });

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
