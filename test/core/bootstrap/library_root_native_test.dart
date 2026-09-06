import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/core/bootstrap/library_root_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android Pioneer filename validation is case-insensitive', () {
    expect(
      validateAndroidPioneerPickerPath(
        '/cache/PIONEERS.STUDYCOLLECTION',
        collection: true,
      ),
      '/cache/PIONEERS.STUDYCOLLECTION',
    );
    expect(
      validateAndroidPioneerPickerPath(
        '/cache/DAR.STUDYBOOK',
        collection: false,
      ),
      '/cache/DAR.STUDYBOOK',
    );
  });

  test('Android Pioneer filename validation explains wrong file types', () {
    expect(
      () => validateAndroidPioneerPickerPath(
        '/cache/DAR.studybook',
        collection: true,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Choose Pioneers.studycollection.',
        ),
      ),
    );
    expect(
      () => validateAndroidPioneerPickerPath(
        '/cache/Pioneers.studycollection',
        collection: false,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Choose a .zip Pioneer package (or legacy .studybook).',
        ),
      ),
    );
  });

  test(
    'Android authorization serializes a persisted read/write tree grant',
    () {
      final authorization = AndroidLibraryAuthorization.fromMap({
        'authorized': true,
        'persistedRead': true,
        'persistedWrite': true,
        'enumerates': true,
        'expectedMarkersFound': true,
        'treeUri':
            'content://com.android.externalstorage.documents/tree/'
            'primary%3ADocuments%2FStudyBible',
        'path': '/app/StudyBibleMirror',
        'displayName': 'StudyBible',
        'fileCount': 480,
        'authorizationState': 'authorized',
        'authorizationTimestamp': 1234,
        'lastReconnect': 1200,
        'lastAuthorizationError': 'previous grant expired',
      });

      expect(authorization.isAuthorized, isTrue);
      expect(authorization.persistedRead, isTrue);
      expect(authorization.persistedWrite, isTrue);
      expect(authorization.enumerates, isTrue);
      expect(authorization.expectedMarkersFound, isTrue);
      expect(authorization.displayName, 'StudyBible');
      expect(authorization.fileCount, 480);
      expect(authorization.authorizationTimestamp, 1234);
      expect(authorization.lastReconnect, 1200);
      expect(authorization.lastAuthorizationError, 'previous grant expired');
    },
  );

  test('saved URI without persisted grant remains unauthorized', () {
    final authorization = AndroidLibraryAuthorization.fromMap({
      'authorized': false,
      'persistedRead': false,
      'persistedWrite': false,
      'enumerates': false,
      'treeUri': 'content://provider/tree/studybible',
      'authorizationState': 'libraryRootAuthorizationMissing',
      'validationError': 'No matching persisted permission.',
    });

    expect(authorization.isAuthorized, isFalse);
    expect(authorization.persistedRead, isFalse);
    expect(authorization.persistedWrite, isFalse);
    expect(authorization.authorizationState, 'libraryRootAuthorizationMissing');
  });

  test('read-only grant is not writable authorization', () {
    final authorization = AndroidLibraryAuthorization.fromMap({
      'authorized': false,
      'persistedRead': true,
      'persistedWrite': false,
      'enumerates': true,
      'expectedMarkersFound': true,
    });

    expect(authorization.persistedRead, isTrue);
    expect(authorization.persistedWrite, isFalse);
    expect(authorization.isAuthorized, isFalse);
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('studybible/library_root'),
          null,
        );
  });

  test(
    'rejects persistent folder selection on iOS with clear guidance',
    () async {
      const channel = MethodChannel('studybible/library_root');
      var nativePickerInvoked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'pickFolder':
                nativePickerInvoked = true;
                return <String, Object?>{
                  'path':
                      '/Users/deanbowen/Library/CloudStorage/OneDrive/CloudFiles',
                  'bookmark': 'folder-bookmark',
                };
            }
            return null;
          });

      await expectLater(
        LibraryRootNative.pickFolder(),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('selecting a .zip Pioneer package'),
          ),
        ),
      );
      expect(nativePickerInvoked, isFalse);
    },
  );

  test('returns the HTML fallback selection on iOS', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'pickScannedHtmlFile':
              return <String, Object?>{
                'path':
                    '/Users/deanbowen/Library/CloudStorage/OneDrive/CloudFiles',
                'bookmark': 'html-bookmark',
              };
          }
          return null;
        });

    final result = await LibraryRootNative.pickScannedHtmlFile();

    expect(
      result?.path,
      '/Users/deanbowen/Library/CloudStorage/OneDrive/CloudFiles',
    );
    expect(result?.bookmark, 'html-bookmark');
  });

  test(
    'returns copied file paths from the import file picker on iOS',
    () async {
      const channel = MethodChannel('studybible/library_root');
      final receivedArguments = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'pickImportFiles':
                receivedArguments.add(call.arguments);
                return <String, Object?>{
                  'paths': <Object?>[
                    '/tmp/Inbox/SSP.html',
                    '/tmp/Inbox/image_0001.png',
                  ],
                };
            }
            return null;
          });

      final result = await LibraryRootNative.pickImportFiles(kind: 'assets');

      expect(result, ['/tmp/Inbox/SSP.html', '/tmp/Inbox/image_0001.png']);
      expect(receivedArguments.single, {'kind': 'assets'});
    },
  );

  test('requests the package kind for .studybook imports on iOS', () async {
    const channel = MethodChannel('studybible/library_root');
    final receivedArguments = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'pickImportFiles':
              receivedArguments.add(call.arguments);
              return <String, Object?>{
                'paths': <Object?>['/tmp/Inbox/SSP07-5-2026.studybook'],
              };
          }
          return null;
        });

    final result = await LibraryRootNative.pickStudyBookPackage();

    expect(result, '/tmp/Inbox/SSP07-5-2026.studybook');
    expect(receivedArguments.single, {'kind': 'bookPackage'});
  });

  test('accepts a plain .zip returned for package import', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pickImportFiles') {
            return <String, Object?>{
              'paths': <Object?>['/tmp/Inbox/SSP07-5-2026.zip'],
            };
          }
          return null;
        });

    final result = await LibraryRootNative.pickStudyBookPackage();

    expect(result, '/tmp/Inbox/SSP07-5-2026.zip');
  });

  test('rejects non-package paths returned for package import', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pickImportFiles') {
            return <String, Object?>{
              'paths': <Object?>['/tmp/Inbox/not-a-package.pdf'],
            };
          }
          return null;
        });

    await expectLater(
      LibraryRootNative.pickStudyBookPackage(),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts a studycollection returned for package import', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pickImportFiles') {
            return <String, Object?>{
              'paths': <Object?>['/tmp/Inbox/Pioneers.studycollection'],
            };
          }
          return null;
        });
    expect(
      await LibraryRootNative.pickStudyCollection(),
      '/tmp/Inbox/Pioneers.studycollection',
    );
  });

  test('collection picker rejects an individual studybook', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {
            'paths': ['/tmp/Inbox/WOR.studybook'],
          },
        );
    await expectLater(
      LibraryRootNative.pickStudyCollection(),
      throwsA(isA<FormatException>()),
    );
  });

  test('one-book picker rejects a studycollection', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {
            'paths': ['/tmp/Inbox/Pioneers.studycollection'],
          },
        );
    await expectLater(
      LibraryRootNative.pickStudyBookPackage(),
      throwsA(isA<FormatException>()),
    );
  });

  test('returns null when the import file picker is cancelled', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'pickImportFiles':
              return null;
          }
          return null;
        });

    final result = await LibraryRootNative.pickImportFiles();

    expect(result, isNull);
  });

  test('returns null when the import file picker returns no paths', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'pickImportFiles':
              return <String, Object?>{'paths': <Object?>[]};
          }
          return null;
        });

    final result = await LibraryRootNative.pickImportFiles();

    expect(result, isNull);
  });

  test('requests one Books parent folder through pickImportFolders', () async {
    const channel = MethodChannel('studybible/library_root');
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          return <String, Object?>{
            'paths': <Object?>['/private/tmp/provider/Books'],
          };
        });

    final result = await LibraryRootNative.pickImportFolders();

    expect(methods, ['pickImportFolders']);
    expect(result, ['/private/tmp/provider/Books']);
  });

  test('returns null when the Books folder picker is cancelled', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    expect(await LibraryRootNative.pickImportFolders(), isNull);
  });

  test('propagates a typed native Books picker error', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'folder_picker_unavailable',
            message: 'Unable to present the book folder picker on iOS.',
          );
        });

    await expectLater(
      LibraryRootNative.pickImportFolders(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'folder_picker_unavailable',
        ),
      ),
    );
  });

  test('returns null when the HTML picker is cancelled', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'pickScannedHtmlFile':
              return null;
          }
          return null;
        });

    final result = await LibraryRootNative.pickScannedHtmlFile();

    expect(result, isNull);
  });
}
