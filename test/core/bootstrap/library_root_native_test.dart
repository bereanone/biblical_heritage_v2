import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/core/bootstrap/library_root_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('returns the native folder picker selection on iOS', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'pickFolder':
              return <String, Object?>{
                'path':
                    '/Users/deanbowen/Library/CloudStorage/OneDrive/CloudFiles',
                'bookmark': 'folder-bookmark',
              };
          }
          return null;
        });

    final result = await LibraryRootNative.pickFolder();

    expect(
      result?.path,
      '/Users/deanbowen/Library/CloudStorage/OneDrive/CloudFiles',
    );
    expect(result?.bookmark, 'folder-bookmark');
  });

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

  test('rejects non-studybook paths returned for package import', () async {
    const channel = MethodChannel('studybible/library_root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pickImportFiles') {
            return <String, Object?>{
              'paths': <Object?>['/tmp/Inbox/not-a-package.zip'],
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
