import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/library_root_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('studybible/library_root');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    LibraryRootNative.debugUsesAndroidDocumentTree = true;
    LibraryRootService.instance.invalidateCachedSelection();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    LibraryRootNative.debugUsesAndroidDocumentTree = null;
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'saved URI with matching read/write grant passes startup gate',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'validateAndroidLibraryTree');
            return <String, Object?>{
              'authorized': true,
              'persistedRead': true,
              'persistedWrite': true,
              'enumerates': true,
              'expectedMarkersFound': true,
              'authorizationState': 'authorized',
            };
          });

      await expectLater(
        LibraryRootService.instance.requireLibraryAuthorization(write: true),
        completes,
      );
    },
  );

  test('saved URI without grant blocks once before batch work', () async {
    var validationCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          validationCalls += 1;
          return <String, Object?>{
            'authorized': false,
            'persistedRead': false,
            'persistedWrite': false,
            'enumerates': false,
            'treeUri': 'content://provider/tree/studybible',
            'authorizationState': 'libraryRootAuthorizationMissing',
            'validationError': 'No matching persisted grant.',
          };
        });

    await expectLater(
      LibraryRootService.instance.requireLibraryAuthorization(write: true),
      throwsA(
        isA<LibraryRootAuthorizationMissing>().having(
          (error) => error.detail,
          'detail',
          'No matching persisted grant.',
        ),
      ),
    );
    expect(validationCalls, 1);
  });

  test('read-only grant blocks writable download work', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'authorized': false,
            'persistedRead': true,
            'persistedWrite': false,
            'enumerates': true,
            'expectedMarkersFound': true,
            'authorizationState': 'libraryRootAuthorizationMissing',
          };
        });

    await expectLater(
      LibraryRootService.instance.requireLibraryAuthorization(write: true),
      throwsA(isA<LibraryRootAuthorizationMissing>()),
    );
  });

  test('URI that cannot enumerate remains blocked', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'authorized': false,
            'persistedRead': true,
            'persistedWrite': true,
            'enumerates': false,
            'expectedMarkersFound': true,
            'authorizationState': 'libraryRootAuthorizationMissing',
            'validationError': 'The selected folder cannot be enumerated.',
          };
        });

    await expectLater(
      LibraryRootService.instance.requireLibraryAuthorization(),
      throwsA(isA<LibraryRootAuthorizationMissing>()),
    );
  });
}
